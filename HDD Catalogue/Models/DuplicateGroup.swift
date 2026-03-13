import Foundation
import SwiftData

@Model
final class DuplicateGroup {
    @Attribute(.unique) var id: UUID
    var groupName: String
    var suggestedAction: String
    var latestVersionId: UUID?
    var isDismissed: Bool
    
    @Relationship(deleteRule: .nullify, inverse: \Project.duplicateGroup)
    var projects: [Project] = []
    
    init(
        groupName: String,
        suggestedAction: String = "",
        latestVersionId: UUID? = nil
    ) {
        self.id = UUID()
        self.groupName = groupName
        self.suggestedAction = suggestedAction
        self.latestVersionId = latestVersionId
        self.isDismissed = false
    }
    
    /// Returns the project identified as the latest version.
    var latestVersion: Project? {
        projects.first { $0.id == latestVersionId }
    }
    
    /// Returns projects sorted by size (largest first).
    var projectsBySize: [Project] {
        projects.sorted { $0.sizeBytes > $1.sizeBytes }
    }
    
    /// Size difference between largest and smallest member.
    var sizeDifference: Int64 {
        guard let maxSize = projects.map(\.sizeBytes).max(),
              let minSize = projects.map(\.sizeBytes).min() else { return 0 }
        return maxSize - minSize
    }
    
    var formattedSizeDifference: String {
        ByteCountFormatter.string(fromByteCount: sizeDifference, countStyle: .file)
    }
}
