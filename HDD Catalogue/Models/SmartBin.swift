import Foundation
import SwiftUI
import SwiftData

// MARK: - Smart Bin Model

@Model
final class SmartBin {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String          // SF Symbol name
    var isPinned: Bool
    var criteriaJSON: String  // Encoded SmartBinCriteria
    var sortOrder: Int
    
    init(
        name: String,
        icon: String = "tray.full",
        isPinned: Bool = true,
        criteria: SmartBinCriteria = SmartBinCriteria(),
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.isPinned = isPinned
        self.criteriaJSON = (try? JSONEncoder().encode(criteria)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.sortOrder = sortOrder
    }
    
    var criteria: SmartBinCriteria {
        get {
            guard let data = criteriaJSON.data(using: .utf8) else { return SmartBinCriteria() }
            return (try? JSONDecoder().decode(SmartBinCriteria.self, from: data)) ?? SmartBinCriteria()
        }
        set {
            criteriaJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
    }
    
    /// Returns projects that match this bin's criteria.
    func matchingProjects(from allProjects: [Project]) -> [Project] {
        let c = criteria
        return allProjects.filter { project in
            // NLE type
            if let nles = c.nleTypes, !nles.isEmpty {
                guard project.detectedNLEs.contains(where: { nles.contains($0) }) else { return false }
            }
            
            // Status
            if let statuses = c.statusValues, !statuses.isEmpty {
                guard statuses.contains(project.statusRaw) else { return false }
            }
            
            // Tags
            if let tags = c.tags, !tags.isEmpty {
                guard tags.allSatisfy({ project.tags.contains($0) }) else { return false }
            }
            
            // Min size
            if let minSize = c.minSizeBytes, minSize > 0 {
                guard project.sizeBytes >= minSize else { return false }
            }
            
            // Max size
            if let maxSize = c.maxSizeBytes, maxSize > 0 {
                guard project.sizeBytes <= maxSize else { return false }
            }
            
            // Date range
            if let from = c.dateFrom {
                guard (project.projectDate ?? .distantPast) >= from else { return false }
            }
            if let to = c.dateTo {
                guard (project.projectDate ?? .distantFuture) <= to else { return false }
            }
            
            // Camera types
            if let cameras = c.cameraTypes, !cameras.isEmpty {
                guard project.cameraSources.contains(where: { cameras.contains($0) }) else { return false }
            }
            
            // Search text
            if let text = c.searchText, !text.isEmpty {
                let q = text.lowercased()
                let matches = project.displayName.lowercased().contains(q) ||
                    project.folderName.lowercased().contains(q) ||
                    project.projectType.lowercased().contains(q) ||
                    project.aiSummary.lowercased().contains(q)
                guard matches else { return false }
            }
            
            return true
        }
    }
}

// MARK: - Smart Bin Criteria

struct SmartBinCriteria: Codable, Equatable {
    var nleTypes: [String]?
    var clientIds: [String]?     // UUIDs as strings for Codable
    var statusValues: [String]?
    var tags: [String]?
    var minSizeBytes: Int64?
    var maxSizeBytes: Int64?
    var dateFrom: Date?
    var dateTo: Date?
    var cameraTypes: [String]?
    var mediaTypes: [String]?
    var searchText: String?
}
