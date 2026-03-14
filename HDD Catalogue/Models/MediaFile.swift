import Foundation
import SwiftData

/// File-level metadata record for deep media indexing.
/// Stores per-file info: path, size, type, and rich metadata (video/image/audio specs + visual tags).
@Model
final class MediaFile {
    @Attribute(.unique) var id: UUID
    var filename: String
    var relativePath: String        // Path relative to project root
    var fileExtension: String       // Lowercased extension (e.g. "mov", "jpg")
    var fileSize: Int64
    var fileTypeRaw: String         // MediaFileType raw value
    var dateModified: Date?
    var dateCreated: Date?
    
    // MARK: - Video Metadata
    var codec: String?              // e.g. "H.265", "ProRes 422 HQ", "H.264"
    var resolution: String?         // e.g. "3840×2160"
    var resolutionWidth: Int?
    var resolutionHeight: Int?
    var frameRate: Double?           // e.g. 23.976, 29.97, 59.94, 120.0
    var duration: Double?            // Seconds
    var colorSpace: String?          // e.g. "Rec. 709", "Rec. 2020", "S-Log3"
    var bitrate: Int64?              // Bits per second
    
    // MARK: - Image / EXIF Metadata
    var cameraModel: String?         // e.g. "ZV-E1", "Canon R5"
    var lens: String?                // e.g. "24-70mm f/2.8"
    var iso: Int?
    var shutterSpeed: String?        // e.g. "1/500"
    var gpsLatitude: Double?
    var gpsLongitude: Double?
    var imageWidth: Int?
    var imageHeight: Int?
    
    // MARK: - Audio Metadata
    var audioCodec: String?          // e.g. "AAC", "PCM", "MP3"
    var sampleRate: Double?          // e.g. 48000.0, 44100.0
    var channels: Int?               // e.g. 1, 2, 6
    var audioDuration: Double?       // Seconds
    
    // MARK: - Visual Tags (from Apple Vision)
    var visualTags: [String]         // e.g. ["sunset", "outdoor", "people"]
    var visualDescription: String    // Ollama-generated description
    var detectedText: String         // OCR text found in the image/frame
    var faceCount: Int               // Number of faces detected
    
    // MARK: - Relationship
    var project: Project?
    
    init(
        filename: String,
        relativePath: String,
        fileExtension: String,
        fileSize: Int64,
        fileType: MediaFileType,
        dateModified: Date? = nil,
        dateCreated: Date? = nil
    ) {
        self.id = UUID()
        self.filename = filename
        self.relativePath = relativePath
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.fileTypeRaw = fileType.rawValue
        self.dateModified = dateModified
        self.dateCreated = dateCreated
        self.visualTags = []
        self.visualDescription = ""
        self.detectedText = ""
        self.faceCount = 0
    }
    
    var fileType: MediaFileType {
        get { MediaFileType(rawValue: fileTypeRaw) ?? .other }
        set { fileTypeRaw = newValue.rawValue }
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var formattedDuration: String? {
        guard let d = duration ?? audioDuration, d > 0 else { return nil }
        let hours = Int(d) / 3600
        let minutes = (Int(d) % 3600) / 60
        let seconds = Int(d) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Short metadata badge for result rows (e.g. "4K 24fps ProRes")
    var metadataBadge: String {
        var parts: [String] = []
        
        switch fileType {
        case .video:
            if let w = resolutionWidth {
                if w >= 7680 { parts.append("8K") }
                else if w >= 3840 { parts.append("4K") }
                else if w >= 2560 { parts.append("QHD") }
                else if w >= 1920 { parts.append("1080p") }
                else if w >= 1280 { parts.append("720p") }
                else { parts.append("\(w)p") }
            }
            if let fps = frameRate {
                if fps == floor(fps) {
                    parts.append("\(Int(fps))fps")
                } else {
                    parts.append(String(format: "%.2gfps", fps))
                }
            }
            if let c = codec {
                // Shorten common codecs
                let short = c.replacingOccurrences(of: "Apple ", with: "")
                    .replacingOccurrences(of: "MPEG-4 Part 10 / ", with: "")
                parts.append(short)
            }
        case .image:
            if let model = cameraModel {
                parts.append(model)
            }
            if let w = imageWidth, let h = imageHeight {
                parts.append("\(w)×\(h)")
            }
        case .audio:
            if let sr = sampleRate {
                parts.append("\(Int(sr / 1000))kHz")
            }
            if let ch = channels {
                parts.append(ch == 1 ? "Mono" : ch == 2 ? "Stereo" : "\(ch)ch")
            }
            if let ac = audioCodec {
                parts.append(ac)
            }
        default:
            break
        }
        
        return parts.joined(separator: " · ")
    }
    
    /// SF Symbol for the file type.
    var typeIcon: String {
        switch fileType {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .projectFile: return "doc.badge.gearshape"
        case .other: return "doc"
        }
    }
    
    /// Color accent for the file type.
    var typeColorName: String {
        switch fileType {
        case .video: return "blue"
        case .audio: return "green"
        case .image: return "purple"
        case .projectFile: return "orange"
        case .other: return "gray"
        }
    }
}

// MARK: - Media File Type

enum MediaFileType: String, Codable, CaseIterable, Identifiable {
    case video = "Video"
    case audio = "Audio"
    case image = "Image"
    case projectFile = "Project File"
    case other = "Other"
    
    var id: String { rawValue }
    
    /// Classify a file extension into a media file type.
    static func classify(_ ext: String) -> MediaFileType {
        let lower = ext.lowercased()
        if MediaSummary.videoExtensions.contains(lower) { return .video }
        if MediaSummary.audioExtensions.contains(lower) { return .audio }
        if MediaSummary.graphicsExtensions.contains(lower) { return .image }
        if NLEDetector.nleExtensions.keys.contains(lower) { return .projectFile }
        // Additional image formats not in graphicsExtensions
        if ["raw", "arw", "cr3", "cr2", "nef", "dng", "raf", "rw2", "orf", "heic", "heif"].contains(lower) {
            return .image
        }
        return .other
    }
}
