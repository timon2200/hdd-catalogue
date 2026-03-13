import Foundation
import SwiftUI
import SwiftData

enum ThumbnailType: String, Codable {
    case icon = "icon"       // SF Symbol name
    case emoji = "emoji"     // Emoji character
    case image = "image"     // User-provided image data
    case auto = "auto"       // Auto-assigned based on project type
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var folderName: String
    var displayName: String
    var folderPath: String
    var projectType: String  // "Web Design", "Video Edit", "Photography", "3D/Motion", "Development", etc.
    var aiSummary: String
    var sizeBytes: Int64
    var fileCount: Int
    var dateModified: Date?
    var dateCreated: Date?
    var isEdited: Bool       // Prevents AI from overwriting manual edits
    
    // Thumbnail
    var thumbnailTypeRaw: String  // ThumbnailType raw value
    @Attribute(.externalStorage) var thumbnailData: Data?
    var thumbnailEmoji: String?
    var thumbnailIconName: String?
    
    // Relationships
    var drive: Drive?
    var client: Client?
    var duplicateGroup: DuplicateGroup?
    
    init(
        folderName: String,
        folderPath: String,
        displayName: String? = nil,
        projectType: String = "Unknown",
        aiSummary: String = "",
        sizeBytes: Int64 = 0,
        fileCount: Int = 0,
        dateModified: Date? = nil,
        dateCreated: Date? = nil
    ) {
        self.id = UUID()
        self.folderName = folderName
        self.displayName = displayName ?? folderName
        self.folderPath = folderPath
        self.projectType = projectType
        self.aiSummary = aiSummary
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
        self.dateModified = dateModified
        self.dateCreated = dateCreated
        self.isEdited = false
        self.thumbnailTypeRaw = ThumbnailType.auto.rawValue
    }
    
    var thumbnailType: ThumbnailType {
        get { ThumbnailType(rawValue: thumbnailTypeRaw) ?? .auto }
        set { thumbnailTypeRaw = newValue.rawValue }
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    
    var formattedDate: String {
        guard let date = dateModified else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    /// Returns the appropriate SF Symbol or emoji for the project type.
    var autoThumbnailEmoji: String {
        switch projectType.lowercased() {
        case let t where t.contains("web"):
            return "🌐"
        case let t where t.contains("video") || t.contains("motion"):
            return "🎬"
        case let t where t.contains("photo"):
            return "📸"
        case let t where t.contains("3d") || t.contains("render"):
            return "🎨"
        case let t where t.contains("dev") || t.contains("code") || t.contains("software"):
            return "💻"
        case let t where t.contains("music") || t.contains("audio"):
            return "🎵"
        case let t where t.contains("brand") || t.contains("logo") || t.contains("identity"):
            return "✏️"
        case let t where t.contains("document") || t.contains("writing"):
            return "📝"
        default:
            return "📁"
        }
    }
    
    /// The display thumbnail — resolves the actual thumbnail to show based on type.
    var resolvedThumbnailEmoji: String {
        switch thumbnailType {
        case .emoji:
            return thumbnailEmoji ?? autoThumbnailEmoji
        case .auto:
            return autoThumbnailEmoji
        default:
            return autoThumbnailEmoji
        }
    }
}
