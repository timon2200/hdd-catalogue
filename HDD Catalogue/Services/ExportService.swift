import Foundation
import AppKit

/// Exports catalogue data to CSV or JSON files.
enum ExportService {
    
    /// Export projects as CSV using NSSavePanel.
    @MainActor
    static func exportCSV(projects: [Project]) {
        let header = "Name,Folder,Drive,Client,Type,Size (bytes),Files,Modified,Summary"
        let rows = projects.map { project in
            let name = escapeCsvField(project.displayName)
            let folder = escapeCsvField(project.folderPath)
            let drive = escapeCsvField(project.drive?.name ?? "")
            let client = escapeCsvField(project.client?.name ?? "")
            let type = escapeCsvField(project.projectType)
            let size = "\(project.sizeBytes)"
            let files = "\(project.fileCount)"
            let modified = project.dateModified.map {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f.string(from: $0)
            } ?? ""
            let summary = escapeCsvField(project.aiSummary)
            return "\(name),\(folder),\(drive),\(client),\(type),\(size),\(files),\(modified),\(summary)"
        }
        
        let csv = ([header] + rows).joined(separator: "\n")
        saveFile(content: csv, defaultName: "hdd-catalogue-export.csv", fileType: "csv")
    }
    
    /// Export projects as JSON using NSSavePanel.
    @MainActor
    static func exportJSON(projects: [Project]) {
        let items = projects.map { project -> [String: Any] in
            var dict: [String: Any] = [
                "name": project.displayName,
                "folderName": project.folderName,
                "folderPath": project.folderPath,
                "projectType": project.projectType,
                "sizeBytes": project.sizeBytes,
                "formattedSize": project.formattedSize,
                "fileCount": project.fileCount,
                "isEdited": project.isEdited,
            ]
            if let drive = project.drive {
                dict["drive"] = [
                    "name": drive.name,
                    "isConnected": drive.isConnected
                ]
            }
            if let client = project.client {
                dict["client"] = [
                    "name": client.name,
                    "color": client.colorHex
                ]
            }
            if !project.aiSummary.isEmpty {
                dict["aiSummary"] = project.aiSummary
            }
            if let modified = project.dateModified {
                let f = ISO8601DateFormatter()
                dict["dateModified"] = f.string(from: modified)
            }
            if let created = project.dateCreated {
                let f = ISO8601DateFormatter()
                dict["dateCreated"] = f.string(from: created)
            }
            return dict
        }
        
        let wrapper: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "projectCount": projects.count,
            "projects": items
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        
        saveFile(content: json, defaultName: "hdd-catalogue-export.json", fileType: "json")
    }
    
    // MARK: - Private Helpers
    
    private static func escapeCsvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
    
    @MainActor
    private static func saveFile(content: String, defaultName: String, fileType: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = fileType == "csv"
            ? [.commaSeparatedText]
            : [.json]
        panel.canCreateDirectories = true
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
