import Foundation
import SwiftData
import AVFoundation
import AppKit
import Vision
import CoreImage
import ImageIO

/// Deep media indexing & search service.
/// Scans every file inside project folders, extracts rich metadata
/// (video/image/audio specs), runs Apple Vision on keyframes & images,
/// and provides unified file-level search across all drives.
@Observable
final class DeepMediaSearchService {
    
    // MARK: - Dependencies
    
    let ollamaService = OllamaService()
    
    // MARK: - Observable State
    
    var isIndexing: Bool = false
    var indexingProgress: Double = 0
    var indexingCurrentProject: String = ""
    var indexingFilesProcessed: Int = 0
    var indexingFilesTotal: Int = 0
    var indexingStatus: String = ""
    
    // MARK: - Constants
    
    private let maxFilesPerProject = 50_000
    private let maxKeyframesPerVideo = 5
    private let keyframeIntervalSeconds: Double = 30.0
    private let visualConfidenceThreshold: Float = 0.15
    
    private let skipDirectories: Set<String> = [
        ".Trash", ".Spotlight-V100", ".fseventsd", ".TemporaryItems",
        ".DS_Store", ".Trashes", ".vol", ".DocumentRevisions-V100",
        ".git", "node_modules", ".svn", "__pycache__",
        ".AppleDouble", ".AppleDB", ".AppleDesktop",
    ]
    
    // MARK: - Deep Indexing
    
    /// Deep-index all files in a single project.
    /// Extracts per-file metadata, visual tags from keyframes/images.
    /// Incremental: skips files that haven't changed since last index.
    func deepIndexProject(_ project: Project, modelContext: ModelContext) async {
        guard project.drive?.isConnected == true else { return }
        
        let projectURL = URL(fileURLWithPath: project.folderPath)
        guard FileManager.default.fileExists(atPath: projectURL.path) else { return }
        
        await MainActor.run {
            indexingCurrentProject = project.displayName
            indexingStatus = "Enumerating files…"
        }
        
        // Check if Ollama is available for descriptions
        let savedModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? "qwen3.5:0.8b"
        ollamaService.currentModel = savedModel
        await ollamaService.checkAvailability()
        ollamaService.resetProgress()
        
        let ollamaReady = ollamaService.isAvailable
        if ollamaReady {
            await MainActor.run {
                indexingStatus = "Ollama ready (\(savedModel)) — will generate descriptions"
            }
        }
        
        // Build a lookup of existing indexed files by relative path
        let existingFiles = project.mediaFiles
        var existingByPath: [String: MediaFile] = [:]
        for file in existingFiles {
            existingByPath[file.relativePath] = file
        }
        
        // Enumerate all files
        var fileURLs: [(url: URL, relativePath: String)] = []
        if let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]) else { continue }
                
                if values.isDirectory == true {
                    if shouldSkipDirectory(fileURL.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                
                let relativePath = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
                fileURLs.append((url: fileURL, relativePath: relativePath))
                
                if fileURLs.count >= maxFilesPerProject { break }
            }
        }
        
        await MainActor.run {
            indexingFilesTotal = fileURLs.count
            indexingFilesProcessed = 0
            indexingStatus = "Processing \(fileURLs.count) files…"
        }
        
        // Process each file
        for (index, item) in fileURLs.enumerated() {
            let url = item.url
            let relativePath = item.relativePath
            
            // Check if already indexed and unchanged
            if let existing = existingByPath[relativePath] {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let existingMod = existing.dateModified, let fileMod = modified, existingMod >= fileMod {
                    // File hasn't changed — but check if it's missing AI enrichment
                    if ollamaReady && existing.visualDescription.isEmpty && existing.fileType == .image {
                        await MainActor.run {
                            indexingStatus = "🤖 Enriching: \(url.lastPathComponent)"
                        }
                        // Add missing OCR, face detection, and description
                        if existing.detectedText.isEmpty {
                            await recognizeText(url: url, into: existing)
                        }
                        if existing.faceCount == 0 {
                            await detectFaces(url: url, into: existing)
                        }
                        if let desc = await ollamaService.describeImageFile(at: url) {
                            existing.visualDescription = desc.description
                            await MainActor.run {
                                indexingStatus = "✅ \(url.lastPathComponent): \(desc.description.prefix(60))…"
                            }
                        }
                    }
                    existingByPath.removeValue(forKey: relativePath)
                    await MainActor.run {
                        indexingFilesProcessed = index + 1
                        indexingProgress = Double(index + 1) / Double(fileURLs.count)
                    }
                    continue
                }
                // File changed — delete old record, will re-create
                modelContext.delete(existing)
                existingByPath.removeValue(forKey: relativePath)
            }
            
            // Create new MediaFile
            guard let resourceValues = try? url.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey, .creationDateKey
            ]) else { continue }
            
            let ext = url.pathExtension.lowercased()
            let fileType = MediaFileType.classify(ext)
            
            let mediaFile = MediaFile(
                filename: url.lastPathComponent,
                relativePath: relativePath,
                fileExtension: ext,
                fileSize: Int64(resourceValues.fileSize ?? 0),
                fileType: fileType,
                dateModified: resourceValues.contentModificationDate,
                dateCreated: resourceValues.creationDate
            )
            
            // Extract type-specific metadata
            switch fileType {
            case .video:
                await extractVideoMetadata(url: url, into: mediaFile)
            case .image:
                extractImageMetadata(url: url, into: mediaFile)
            case .audio:
                await extractAudioMetadata(url: url, into: mediaFile)
            case .projectFile, .other:
                break
            }
            
            // Visual tagging for images (skip large projects to keep indexing fast)
            if fileType == .image && fileURLs.count < 10_000 {
                await MainActor.run {
                    indexingStatus = "🏷️ Classifying: \(url.lastPathComponent)"
                }
                await classifyFile(url: url, into: mediaFile)
                await recognizeText(url: url, into: mediaFile)
                await detectFaces(url: url, into: mediaFile)
                
                // Ollama description (if available)
                if ollamaReady {
                    await MainActor.run {
                        indexingStatus = "🤖 AI describing: \(url.lastPathComponent)"
                    }
                    if let desc = await ollamaService.describeImageFile(at: url) {
                        mediaFile.visualDescription = desc.description
                        await MainActor.run {
                            indexingStatus = "✅ \(url.lastPathComponent): \(desc.description.prefix(60))…"
                        }
                    }
                }
            }
            
            mediaFile.project = project
            modelContext.insert(mediaFile)
            
            await MainActor.run {
                indexingFilesProcessed = index + 1
                indexingProgress = Double(index + 1) / Double(fileURLs.count)
            }
            
            // Yield periodically for UI responsiveness
            if index % 50 == 0 {
                try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
            }
        }
        
        // Remove MediaFiles that no longer exist on disk
        for (_, orphan) in existingByPath {
            modelContext.delete(orphan)
        }
        
        project.isDeepIndexed = true
        project.lastDeepIndexDate = Date()
        try? modelContext.save()
    }
    
    /// Deep-index multiple projects with progress tracking.
    func deepIndexProjects(_ projects: [Project], modelContext: ModelContext) async {
        let toIndex = projects.filter { $0.drive?.isConnected == true }
        guard !toIndex.isEmpty else { return }
        
        await MainActor.run {
            isIndexing = true
            indexingProgress = 0
        }
        
        for (idx, project) in toIndex.enumerated() {
            await MainActor.run {
                indexingStatus = "Indexing \(idx + 1)/\(toIndex.count): \(project.displayName)"
            }
            
            await deepIndexProject(project, modelContext: modelContext)
            
            await MainActor.run {
                indexingProgress = Double(idx + 1) / Double(toIndex.count)
            }
        }
        
        await MainActor.run {
            isIndexing = false
            indexingProgress = 1.0
            indexingStatus = ""
            indexingCurrentProject = ""
        }
    }
    
    // MARK: - Search
    
    /// Search across all indexed media files.
    func searchFiles(query: String, allProjects: [Project], filters: FileSearchFilter = FileSearchFilter()) -> [FileSearchResult] {
        let queryTerms = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }
        
        var results: [FileSearchResult] = []
        
        for project in allProjects where project.isDeepIndexed {
            for file in project.mediaFiles {
                // Apply type filter
                if let type = filters.fileType, file.fileType != type { continue }
                
                // Apply spec filters
                if let minWidth = filters.minResolutionWidth, (file.resolutionWidth ?? file.imageWidth ?? 0) < minWidth { continue }
                if let codec = filters.codec, !(file.codec ?? "").lowercased().contains(codec.lowercased()) { continue }
                if let minFps = filters.minFrameRate, (file.frameRate ?? 0) < minFps { continue }
                if let camera = filters.cameraModel, !(file.cameraModel ?? "").lowercased().contains(camera.lowercased()) { continue }
                if let minSize = filters.minSize, file.fileSize < minSize { continue }
                if let maxSize = filters.maxSize, file.fileSize > maxSize { continue }
                
                // Text search
                var relevance: Double = 0
                
                if queryTerms.isEmpty && filters.hasActiveFilters {
                    // Filter-only search — all matching files are relevant
                    relevance = 1.0
                } else if !queryTerms.isEmpty {
                    let searchable = [
                        file.filename.lowercased(),
                        file.relativePath.lowercased(),
                        (file.codec ?? "").lowercased(),
                        (file.cameraModel ?? "").lowercased(),
                        (file.audioCodec ?? "").lowercased(),
                        (file.colorSpace ?? "").lowercased(),
                        file.visualDescription.lowercased(),
                        file.detectedText.lowercased(),
                    ] + file.visualTags.map { $0.lowercased() }
                    
                    var matchCount = 0
                    for term in queryTerms {
                        if searchable.contains(where: { $0.contains(term) }) {
                            matchCount += 1
                        }
                    }
                    
                    guard matchCount > 0 else { continue }
                    relevance = Double(matchCount) / Double(queryTerms.count)
                } else {
                    continue // No query and no filters
                }
                
                results.append(FileSearchResult(
                    file: file,
                    project: project,
                    drive: project.drive,
                    relevance: relevance
                ))
            }
        }
        
        return results
            .sorted { $0.relevance > $1.relevance }
            .prefix(200)
            .map { $0 }
    }
    
    // MARK: - Video Metadata Extraction
    
    private func extractVideoMetadata(url: URL, into file: MediaFile) async {
        let asset = AVAsset(url: url)
        
        // Duration
        if let duration = try? await asset.load(.duration) {
            file.duration = CMTimeGetSeconds(duration)
        }
        
        // Video track info
        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track = tracks.first {
            // Resolution
            if let size = try? await track.load(.naturalSize) {
                file.resolutionWidth = Int(size.width)
                file.resolutionHeight = Int(size.height)
                file.resolution = "\(Int(size.width))×\(Int(size.height))"
            }
            
            // Frame rate
            if let fps = try? await track.load(.nominalFrameRate) {
                file.frameRate = Double(fps)
            }
            
            // Estimated bitrate
            if let bitrate = try? await track.load(.estimatedDataRate) {
                file.bitrate = Int64(bitrate)
            }
            
            // Codec via format descriptions
            if let descriptions = try? await track.load(.formatDescriptions),
               let desc = descriptions.first {
                let codecType = CMFormatDescriptionGetMediaSubType(desc)
                file.codec = codecName(from: codecType)
                
                // Color space from extensions
                if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
                    if let colorPrimaries = extensions["ColorPrimaries"] as? String {
                        file.colorSpace = colorPrimaries
                    }
                }
            }
        }
        
        // Keyframe extraction + visual classification
        await extractAndClassifyKeyframes(url: url, asset: asset, into: file)
    }
    
    /// Extract keyframes and classify them with Apple Vision.
    private func extractAndClassifyKeyframes(url: URL, asset: AVAsset, into file: MediaFile) async {
        guard let duration = try? await asset.load(.duration) else { return }
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return }
        
        // Calculate keyframe times
        var times: [CMTime] = []
        var t: Double = 0
        while t < totalSeconds && times.count < maxKeyframesPerVideo {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += keyframeIntervalSeconds
        }
        if times.isEmpty { return }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640) // Keep it fast
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        
        var allTags: Set<String> = []
        
        for time in times {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let tags = try await classifyImage(cgImage)
                for tag in tags {
                    allTags.insert(tag)
                }
            } catch {
                continue
            }
        }
        
        if !allTags.isEmpty {
            file.visualTags = Array(allTags).sorted()
        }
        
        // Ollama description from first keyframe (if available)
        if ollamaService.isAvailable && !times.isEmpty {
            do {
                let (cgImage, _) = try await generator.image(at: times[0])
                await MainActor.run {
                    indexingStatus = "🤖 AI describing video: \(file.filename)"
                }
                if let desc = await ollamaService.describeImage(cgImage, filename: file.filename) {
                    file.visualDescription = desc.description
                    await MainActor.run {
                        indexingStatus = "✅ \(file.filename): \(desc.description.prefix(60))…"
                    }
                }
            } catch {}
        }
    }
    
    // MARK: - Image Metadata Extraction (EXIF)
    
    private func extractImageMetadata(url: URL, into file: MediaFile) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return }
        
        // Image dimensions
        if let width = properties[kCGImagePropertyPixelWidth as String] as? Int {
            file.imageWidth = width
        }
        if let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
            file.imageHeight = height
        }
        
        // EXIF data
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first {
                file.iso = iso
            }
            if let exposure = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                if exposure >= 1 {
                    file.shutterSpeed = "\(Int(exposure))s"
                } else {
                    file.shutterSpeed = "1/\(Int(1.0 / exposure))"
                }
            }
            if let focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double,
               let fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double {
                file.lens = "\(Int(focalLength))mm f/\(String(format: "%.1g", fNumber))"
            }
        }
        
        // TIFF data (camera model)
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            if let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
                file.cameraModel = model.trimmingCharacters(in: .whitespaces)
            }
        }
        
        // GPS data
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String {
                file.gpsLatitude = latRef == "S" ? -lat : lat
            }
            if let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String {
                file.gpsLongitude = lonRef == "W" ? -lon : lon
            }
        }
    }
    
    // MARK: - Audio Metadata Extraction
    
    private func extractAudioMetadata(url: URL, into file: MediaFile) async {
        let asset = AVAsset(url: url)
        
        if let duration = try? await asset.load(.duration) {
            file.audioDuration = CMTimeGetSeconds(duration)
        }
        
        if let tracks = try? await asset.loadTracks(withMediaType: .audio),
           let track = tracks.first {
            if let descriptions = try? await track.load(.formatDescriptions),
               let desc = descriptions.first {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                if let sbd = asbd?.pointee {
                    file.sampleRate = sbd.mSampleRate
                    file.channels = Int(sbd.mChannelsPerFrame)
                }
                
                let codecType = CMFormatDescriptionGetMediaSubType(desc)
                file.audioCodec = audioCodecName(from: codecType)
            }
        }
    }
    
    // MARK: - Apple Vision Classification
    
    private func classifyFile(url: URL, into file: MediaFile) async {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        
        do {
            let tags = try await classifyImage(cgImage)
            if !tags.isEmpty {
                file.visualTags = tags
            }
        } catch {
            // Classification failed — not critical
        }
    }
    
    private func classifyImage(_ cgImage: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let results = observations
                    .filter { $0.confidence >= 0.15 }
                    .prefix(10)
                    .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
                
                continuation.resume(returning: Array(results))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Text Recognition (OCR)
    
    private func recognizeText(url: URL, into file: MediaFile) async {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        
        do {
            let text = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: "")
                        return
                    }
                    let texts = observations.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: texts.joined(separator: " "))
                }
                request.recognitionLevel = .fast
                request.usesLanguageCorrection = false
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            if !text.isEmpty {
                file.detectedText = String(text.prefix(500)) // Cap at 500 chars
            }
        } catch {}
    }
    
    // MARK: - Face Detection
    
    private func detectFaces(url: URL, into file: MediaFile) async {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        
        do {
            let count = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                let request = VNDetectFaceRectanglesRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let faces = request.results as? [VNFaceObservation] ?? []
                    continuation.resume(returning: faces.count)
                }
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            file.faceCount = count
            if count > 0 && !file.visualTags.contains("people") {
                file.visualTags.append("people")
            }
        } catch {}
    }
    
    // MARK: - Helpers
    
    private func shouldSkipDirectory(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        return skipDirectories.contains(name)
    }
    
    private func codecName(from fourCC: FourCharCode) -> String {
        switch fourCC {
        case kCMVideoCodecType_H264:                return "H.264"
        case kCMVideoCodecType_HEVC:                return "H.265"
        case kCMVideoCodecType_AppleProRes4444:     return "ProRes 4444"
        case kCMVideoCodecType_AppleProRes422HQ:    return "ProRes 422 HQ"
        case kCMVideoCodecType_AppleProRes422:      return "ProRes 422"
        case kCMVideoCodecType_AppleProRes422LT:    return "ProRes 422 LT"
        case kCMVideoCodecType_AppleProRes422Proxy: return "ProRes Proxy"
        case kCMVideoCodecType_AppleProResRAW:      return "ProRes RAW"
        case kCMVideoCodecType_AppleProResRAWHQ:    return "ProRes RAW HQ"
        default:
            // Convert FourCharCode to readable string
            let bytes: [Character] = [
                Character(Unicode.Scalar((fourCC >> 24) & 0xFF)!),
                Character(Unicode.Scalar((fourCC >> 16) & 0xFF)!),
                Character(Unicode.Scalar((fourCC >> 8) & 0xFF)!),
                Character(Unicode.Scalar(fourCC & 0xFF)!),
            ]
            return String(bytes).trimmingCharacters(in: .whitespaces)
        }
    }
    
    private func audioCodecName(from fourCC: FourCharCode) -> String {
        switch fourCC {
        case kAudioFormatLinearPCM:         return "PCM"
        case kAudioFormatMPEG4AAC:          return "AAC"
        case kAudioFormatMPEGLayer3:        return "MP3"
        case kAudioFormatAppleLossless:     return "ALAC"
        case kAudioFormatFLAC:              return "FLAC"
        case kAudioFormatAC3:               return "AC-3"
        case kAudioFormatEnhancedAC3:       return "E-AC-3"
        default:
            return "Audio"
        }
    }
}

// MARK: - Search Types

/// Filters for deep media file search.
struct FileSearchFilter {
    var fileType: MediaFileType?
    var minResolutionWidth: Int?      // e.g. 3840 for 4K
    var codec: String?                 // e.g. "ProRes"
    var minFrameRate: Double?          // e.g. 120.0
    var cameraModel: String?
    var minSize: Int64?
    var maxSize: Int64?
    
    var hasActiveFilters: Bool {
        fileType != nil || minResolutionWidth != nil || codec != nil ||
        minFrameRate != nil || cameraModel != nil || minSize != nil || maxSize != nil
    }
}

/// A single file search result with context.
struct FileSearchResult: Identifiable {
    let file: MediaFile
    let project: Project
    let drive: Drive?
    let relevance: Double
    
    var id: UUID { file.id }
}
