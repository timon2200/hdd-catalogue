import Foundation
import SwiftUI
import SwiftData

enum ThumbnailType: String, Codable {
    case icon = "icon"           // SF Symbol name
    case emoji = "emoji"         // Emoji character
    case image = "image"         // User-provided image data
    case auto = "auto"           // Auto-assigned based on project type
    case videoFrame = "videoFrame" // Auto-extracted video frame
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
    
    // Phase 1: NLE Detection
    var detectedNLEs: [String]       // e.g. ["Premiere Pro", "After Effects"]
    var nleProjectFileDate: Date?    // Date from NLE project file (more accurate)
    
    // Phase 1: Media Summary (JSON-encoded MediaSummary)
    var mediaSummaryJSON: String?
    
    // Phase 1: Render / Export Detection
    var hasExports: Bool
    var isDelivered: Bool
    
    // Phase 1: Camera Source Detection
    var cameraSources: [String]      // e.g. ["ZV-E1", "Mavic 4 Pro"]
    var hasDroneFootage: Bool
    
    // Phase 1: Shoot-Day Grouping
    var shootDayCount: Int
    var shootDayFolders: [String]    // e.g. ["Proizvodnja 1", "Proizvodnja 2"]
    
    // Phase 1: Project Structure
    var projectCompleteness: Double  // 0.0–1.0
    
    // Phase 2: Tags & Notes
    var tags: [String]               // e.g. ["#urgent", "#archived", "#youtube"]
    var notes: String                // User's free-text note
    
    // Phase 2: Project Status Workflow
    var statusRaw: String            // ProjectStatus raw value
    
    // Phase 2: AI Visual Search
    var visualTags: [String]         // e.g. ["sunset", "interview", "outdoor", "aerial"]
    var visualDescription: String    // AI-generated description of visual content
    
    // Phase 5: Deep Media Index
    var isDeepIndexed: Bool
    var lastDeepIndexDate: Date?
    
    // Relationships
    var drive: Drive?
    var client: Client?
    var duplicateGroup: DuplicateGroup?
    
    @Relationship(deleteRule: .cascade, inverse: \MediaFile.project)
    var mediaFiles: [MediaFile] = []
    
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
        
        // Phase 1 defaults
        self.detectedNLEs = []
        self.hasExports = false
        self.isDelivered = false
        self.cameraSources = []
        self.hasDroneFootage = false
        self.shootDayCount = 0
        self.shootDayFolders = []
        self.projectCompleteness = 0.0
        
        // Phase 2 defaults
        self.tags = []
        self.notes = ""
        self.visualTags = []
        self.visualDescription = ""
        self.statusRaw = ProjectStatus.new.rawValue
        
        // Phase 5 defaults
        self.isDeepIndexed = false
        self.lastDeepIndexDate = nil
    }
    
    var thumbnailType: ThumbnailType {
        get { ThumbnailType(rawValue: thumbnailTypeRaw) ?? .auto }
        set { thumbnailTypeRaw = newValue.rawValue }
    }
    
    var projectStatus: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .new }
        set { statusRaw = newValue.rawValue }
    }
    
    /// Whether this project has been visually indexed by AI.
    var isVisuallyIndexed: Bool {
        !visualTags.isEmpty
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    
    var formattedDate: String {
        guard let date = projectDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    /// Best date for this project — prefers NLE project file date over folder date.
    var projectDate: Date? {
        nleProjectFileDate ?? dateModified
    }
    
    /// Decoded media summary from JSON.
    var mediaSummary: MediaSummary? {
        get {
            guard let json = mediaSummaryJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(MediaSummary.self, from: data)
        }
        set {
            guard let value = newValue,
                  let data = try? JSONEncoder().encode(value) else {
                mediaSummaryJSON = nil
                return
            }
            mediaSummaryJSON = String(data: data, encoding: .utf8)
        }
    }
    
    /// The dominant media type in this project.
    var dominantMediaType: String {
        mediaSummary?.dominantType ?? "Unknown"
    }
    
    /// SF Symbol names for each detected NLE.
    var nleIcons: [(name: String, symbol: String, abbreviation: String)] {
        detectedNLEs.map { nle in
            (nle, NLEDetector.sfSymbol(for: nle), NLEDetector.abbreviation(for: nle))
        }
    }
    
    /// Returns the appropriate SF Symbol or emoji for the project type.
    var autoThumbnailEmoji: String {
        // If NLEs are detected, prefer video-specific emoji
        if !detectedNLEs.isEmpty {
            if detectedNLEs.contains("DaVinci Resolve") { return "🎨" }
            if detectedNLEs.contains("After Effects") { return "✨" }
            return "🎬"
        }
        
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

// MARK: - Project Status

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case new = "New"
    case inProgress = "In Progress"
    case review = "Review"
    case delivered = "Delivered"
    case archived = "Archived"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .new: return .blue
        case .inProgress: return .orange
        case .review: return .purple
        case .delivered: return .green
        case .archived: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .new: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .review: return "eye.circle"
        case .delivered: return "checkmark.circle.fill"
        case .archived: return "archivebox"
        }
    }
}
