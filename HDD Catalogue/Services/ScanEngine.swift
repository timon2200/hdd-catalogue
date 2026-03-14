import Foundation
import SwiftData

/// Asynchronously scans drives for project folders, extracts metadata,
/// and performs Phase 1 deep analysis (NLE, media, cameras, exports, structure).
@Observable
final class ScanEngine {
    var isScanning: Bool = false
    var scanProgress: Double = 0.0
    var currentFolder: String = ""
    var scannedCount: Int = 0
    var totalCount: Int = 0
    
    /// Directories to skip during scanning.
    private let skipDirectories: Set<String> = [
        ".Trash", ".Spotlight-V100", ".fseventsd", ".TemporaryItems",
        ".DS_Store", ".Trashes", ".vol", ".DocumentRevisions-V100",
        "System Volume Information", "$RECYCLE.BIN", "RECYCLER",
        ".git", "node_modules", ".svn", "__pycache__",
        ".AppleDouble", ".AppleDB", ".AppleDesktop",
    ]
    
    /// Scan a drive's folder structure and return project entries.
    @MainActor
    func scanDrive(_ drive: Drive, modelContext: ModelContext, maxDepth: Int = 1) async -> [Project] {
        guard drive.isConnected else { return [] }
        
        let volumeURL = URL(fileURLWithPath: drive.volumePath)
        guard FileManager.default.fileExists(atPath: volumeURL.path) else { return [] }
        
        isScanning = true
        scanProgress = 0.0
        scannedCount = 0
        currentFolder = drive.name
        
        // Discover all project directories up to maxDepth
        let projectURLs = discoverProjectDirectories(at: volumeURL, maxDepth: maxDepth)
        let total = projectURLs.count
        totalCount = total
        
        var projects: [Project] = []
        
        for (index, itemURL) in projectURLs.enumerated() {
            let folderName = itemURL.lastPathComponent
            
            currentFolder = folderName
            scannedCount = index + 1
            scanProgress = total > 0 ? Double(index + 1) / Double(total) : 0
            
            // Check if this project already exists for this drive
            let folderPath = itemURL.path
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.folderPath == folderPath }
            )
            
            if let existingProject = try? modelContext.fetch(descriptor).first {
                // Update metadata but preserve user edits
                let analysis = await analyzeProject(at: itemURL)
                existingProject.sizeBytes = analysis.size
                existingProject.fileCount = analysis.fileCount
                if let modified = analysis.dateModified {
                    existingProject.dateModified = modified
                }
                // Update Phase 1 analysis data (always refresh)
                applyAnalysis(analysis, to: existingProject)
                projects.append(existingProject)
            } else {
                // Create new project entry
                let analysis = await analyzeProject(at: itemURL)
                let project = Project(
                    folderName: folderName,
                    folderPath: itemURL.path,
                    sizeBytes: analysis.size,
                    fileCount: analysis.fileCount,
                    dateModified: analysis.dateModified,
                    dateCreated: analysis.dateCreated
                )
                project.drive = drive
                applyAnalysis(analysis, to: project)
                projects.append(project)
            }
            
            // Small delay to keep UI responsive and show progress
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        // Update drive's last scanned timestamp
        drive.lastScanned = Date()
        
        isScanning = false
        scanProgress = 1.0
        currentFolder = ""
        
        return projects
    }
    
    // MARK: - Private: Project Discovery
    
    /// Recursively discovers project directories up to `maxDepth` levels.
    private func discoverProjectDirectories(at url: URL, maxDepth: Int, currentDepth: Int = 1) -> [URL] {
        let subdirectories = getDirectories(at: url)
        
        // At max depth, treat all directories as projects
        if currentDepth >= maxDepth {
            return subdirectories
        }
        
        var projectURLs: [URL] = []
        
        for dir in subdirectories {
            if directoryContainsFiles(dir) {
                projectURLs.append(dir)
            } else {
                let nested = discoverProjectDirectories(at: dir, maxDepth: maxDepth, currentDepth: currentDepth + 1)
                if nested.isEmpty {
                    projectURLs.append(dir)
                } else {
                    projectURLs.append(contentsOf: nested)
                }
            }
        }
        
        return projectURLs
    }
    
    private func directoryContainsFiles(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        
        return contents.contains { itemURL in
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return !isDir
        }
    }
    
    private func getDirectories(at url: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        return contents.filter { itemURL in
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return isDir && !shouldSkip(itemURL.lastPathComponent)
        }
    }
    
    private func shouldSkip(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        return skipDirectories.contains(name)
    }
    
    // MARK: - Phase 1: Deep Project Analysis
    
    /// Single-pass analysis of a project folder, extracting all Phase 1 data.
    private nonisolated func analyzeProject(at url: URL) async -> ProjectAnalysis {
        var totalSize: Int64 = 0
        var fileCount = 0
        var dateModified: Date?
        var dateCreated: Date?
        
        // Phase 1 analysis accumulators
        var detectedNLEs: Set<String> = []
        var nleProjectFileDate: Date?
        var mediaSummary = MediaSummary()
        var hasExports = false
        var isDelivered = false
        var cameraSources: Set<String> = []
        var hasDroneFootage = false
        var shootDayFolders: [String] = []
        var hasSources = false
        var hasNLE = false
        var subfolderCategories: [String: String] = [:]
        
        // Get folder-level dates
        if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) {
            dateModified = values.contentModificationDate
            dateCreated = values.creationDate
        }
        
        // Analyze top-level subfolders for structure detection
        if let topLevelContents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for item in topLevelContents {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let name = item.lastPathComponent
                let nameLower = name.lowercased()
                
                if isDir {
                    // Export/render folder detection
                    if NLEDetector.exportFolderNames.contains(nameLower) {
                        hasExports = true
                        subfolderCategories[name] = "Exports"
                        // Check if export folder actually has files = delivered
                        if directoryContainsFiles(item) {
                            isDelivered = true
                        }
                    }
                    
                    // Camera source detection
                    let cameraMatch = detectCameraSource(name: name)
                    if let camera = cameraMatch {
                        cameraSources.insert(camera)
                        hasSources = true
                        subfolderCategories[name] = "Source Footage"
                    }
                    
                    // Drone detection
                    if detectDrone(name: name) {
                        hasDroneFootage = true
                        hasSources = true
                    }
                    
                    // Shoot-day detection
                    if detectShootDay(name: name) {
                        shootDayFolders.append(name)
                    }
                    
                    // NLE workspace detection
                    if nameLower.contains("premiere") || nameLower.contains("davinci") ||
                       nameLower.contains("resolve") || nameLower.contains("fcp") ||
                       nameLower.contains("final cut") || nameLower.contains("nle") {
                        subfolderCategories[name] = "NLE Workspace"
                    }
                    
                    // Materials/assets detection
                    if nameLower.contains("mat") || nameLower.contains("material") ||
                       nameLower.contains("asset") || nameLower.contains("stock") ||
                       nameLower.contains("overlay") {
                        subfolderCategories[name] = "Materials"
                    }
                    
                    // Audio detection
                    if nameLower == "audio" || nameLower == "music" || nameLower == "sfx" ||
                       nameLower == "sound" || nameLower == "sounds" || nameLower == "vo" {
                        subfolderCategories[name] = "Audio"
                    }
                    
                    // Graphics detection
                    if nameLower == "graphics" || nameLower == "gfx" || nameLower == "titles" {
                        subfolderCategories[name] = "Graphics"
                    }
                } else {
                    // Top-level file — check for NLE project files
                    let ext = item.pathExtension.lowercased()
                    if let nle = NLEDetector.nleExtensions[ext] {
                        detectedNLEs.insert(nle)
                        hasNLE = true
                        // Get the NLE file's modification date
                        if let fileValues = try? item.resourceValues(forKeys: [.contentModificationDateKey]) {
                            let fileDate = fileValues.contentModificationDate
                            if let existing = nleProjectFileDate {
                                if let fd = fileDate, fd > existing {
                                    nleProjectFileDate = fd
                                }
                            } else {
                                nleProjectFileDate = fileDate
                            }
                        }
                    }
                }
            }
        }
        
        // Full file enumeration for size, file count, media summary, and deep NLE detection
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey]) else { continue }
                let isDir = values.isDirectory ?? false
                
                if !isDir {
                    totalSize += Int64(values.fileSize ?? 0)
                    fileCount += 1
                    
                    let ext = fileURL.pathExtension.lowercased()
                    
                    // NLE detection (also check deep files)
                    if let nle = NLEDetector.nleExtensions[ext] {
                        detectedNLEs.insert(nle)
                        hasNLE = true
                        
                        // Use NLE file modification date (pick the latest)
                        if let fileDate = values.contentModificationDate {
                            if let existing = nleProjectFileDate {
                                if fileDate > existing {
                                    nleProjectFileDate = fileDate
                                }
                            } else {
                                nleProjectFileDate = fileDate
                            }
                        }
                    }
                    
                    // Media summary
                    if let category = MediaSummary.category(for: ext) {
                        switch category {
                        case .video:    mediaSummary.videoCount += 1
                        case .audio:    mediaSummary.audioCount += 1
                        case .graphics: mediaSummary.graphicsCount += 1
                        case .font:     mediaSummary.fontCount += 1
                        case .render:   mediaSummary.renderCount += 1
                        }
                    }
                    
                    // Check if file is in an export folder → count as render
                    let parentName = fileURL.deletingLastPathComponent().lastPathComponent.lowercased()
                    if NLEDetector.exportFolderNames.contains(parentName) {
                        mediaSummary.renderCount += 1
                    }
                    
                    // Source footage detection via RAW formats
                    if ["r3d", "braw", "ari"].contains(ext) {
                        hasSources = true
                    }
                }
                
                // Performance: limit deep enumeration for very large folders
                if fileCount > 50_000 {
                    break
                }
            }
        }
        
        // If we found video files, that counts as having sources
        if mediaSummary.videoCount > 0 {
            hasSources = true
        }
        
        // Completeness scoring: sources (0.33) + NLE (0.33) + exports (0.33)
        var completeness: Double = 0.0
        if hasSources { completeness += 0.33 }
        if hasNLE { completeness += 0.33 }
        if hasExports { completeness += 0.34 }
        
        return ProjectAnalysis(
            size: totalSize,
            fileCount: fileCount,
            dateModified: dateModified,
            dateCreated: dateCreated,
            detectedNLEs: Array(detectedNLEs).sorted(),
            nleProjectFileDate: nleProjectFileDate,
            mediaSummary: mediaSummary,
            hasExports: hasExports,
            isDelivered: isDelivered,
            cameraSources: Array(cameraSources).sorted(),
            hasDroneFootage: hasDroneFootage,
            shootDayFolders: shootDayFolders.sorted(),
            projectCompleteness: completeness
        )
    }
    
    /// Apply analysis results to a Project model object.
    private func applyAnalysis(_ analysis: ProjectAnalysis, to project: Project) {
        project.detectedNLEs = analysis.detectedNLEs
        project.nleProjectFileDate = analysis.nleProjectFileDate
        project.mediaSummary = analysis.mediaSummary
        project.hasExports = analysis.hasExports
        project.isDelivered = analysis.isDelivered
        project.cameraSources = analysis.cameraSources
        project.hasDroneFootage = analysis.hasDroneFootage
        project.shootDayCount = analysis.shootDayFolders.count
        project.shootDayFolders = analysis.shootDayFolders
        project.projectCompleteness = analysis.projectCompleteness
    }
    
    // MARK: - Detection Helpers
    
    /// Check if a folder name matches a known camera model.
    private nonisolated func detectCameraSource(name: String) -> String? {
        let upper = name.uppercased()
        for pattern in NLEDetector.knownCameraPatterns {
            if upper.contains(pattern.uppercased()) {
                return pattern
            }
        }
        return nil
    }
    
    /// Check if a folder name suggests drone footage.
    private nonisolated func detectDrone(name: String) -> Bool {
        let upper = name.uppercased()
        for pattern in NLEDetector.dronePatterns {
            if upper.contains(pattern.uppercased()) {
                return true
            }
        }
        return false
    }
    
    /// Check if a folder name matches shoot-day patterns.
    private nonisolated func detectShootDay(name: String) -> Bool {
        let lower = name.lowercased()
        
        // Check numbered patterns: "proizvodnja 1", "shoot day 2", "day 3", "dan 1"
        for pattern in NLEDetector.shootDayPatterns {
            if lower.hasPrefix(pattern) {
                return true
            }
        }
        
        // Check date-based folder names: "2025-03-12", "20250312"
        let dateRegex = try? NSRegularExpression(pattern: #"^\d{4}[-_]?\d{2}[-_]?\d{2}$"#)
        if let regex = dateRegex {
            let range = NSRange(lower.startIndex..., in: lower)
            if regex.firstMatch(in: lower, range: range) != nil {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Supporting Types

/// Complete analysis result for a project folder.
struct ProjectAnalysis: Sendable {
    let size: Int64
    let fileCount: Int
    let dateModified: Date?
    let dateCreated: Date?
    
    // Phase 1
    let detectedNLEs: [String]
    let nleProjectFileDate: Date?
    let mediaSummary: MediaSummary
    let hasExports: Bool
    let isDelivered: Bool
    let cameraSources: [String]
    let hasDroneFootage: Bool
    let shootDayFolders: [String]
    let projectCompleteness: Double
}
