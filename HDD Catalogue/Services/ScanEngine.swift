import Foundation
import SwiftData

/// Asynchronously scans drives for project folders and extracts metadata.
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
    func scanDrive(_ drive: Drive, modelContext: ModelContext) async -> [Project] {
        guard drive.isConnected else { return [] }
        
        let volumeURL = URL(fileURLWithPath: drive.volumePath)
        
        guard FileManager.default.fileExists(atPath: volumeURL.path) else { return [] }
        
        isScanning = true
        scanProgress = 0.0
        scannedCount = 0
        currentFolder = drive.name
        
        // First pass: count top-level directories for progress reporting
        let topLevelItems = getDirectories(at: volumeURL)
        let total = topLevelItems.count
        totalCount = total
        
        var projects: [Project] = []
        
        for (index, itemURL) in topLevelItems.enumerated() {
            let folderName = itemURL.lastPathComponent
            
            // Skip system/hidden directories
            if shouldSkip(folderName) { continue }
            
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
                let metadata = await extractMetadata(from: itemURL)
                existingProject.sizeBytes = metadata.size
                existingProject.fileCount = metadata.fileCount
                if let modified = metadata.dateModified {
                    existingProject.dateModified = modified
                }
                projects.append(existingProject)
            } else {
                // Create new project entry
                let metadata = await extractMetadata(from: itemURL)
                let project = Project(
                    folderName: folderName,
                    folderPath: itemURL.path,
                    sizeBytes: metadata.size,
                    fileCount: metadata.fileCount,
                    dateModified: metadata.dateModified,
                    dateCreated: metadata.dateCreated
                )
                project.drive = drive
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
    
    // MARK: - Private Helpers
    
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
    
    private nonisolated func extractMetadata(from url: URL) async -> FolderMetadata {
        // Get folder size and file count by enumerating contents
        var totalSize: Int64 = 0
        var fileCount = 0
        var dateModified: Date?
        var dateCreated: Date?
        
        // Get folder-level dates
        if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) {
            dateModified = values.contentModificationDate
            dateCreated = values.creationDate
        }
        
        // Enumerate files for size calculation (limit depth for performance)
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else { continue }
                let isDir = values.isDirectory ?? false
                if !isDir {
                    totalSize += Int64(values.fileSize ?? 0)
                    fileCount += 1
                }
                
                // Performance: limit deep enumeration for very large folders
                if fileCount > 50_000 {
                    break
                }
            }
        }
        
        return FolderMetadata(
            size: totalSize,
            fileCount: fileCount,
            dateModified: dateModified,
            dateCreated: dateCreated
        )
    }
}

// MARK: - Supporting Types

struct FolderMetadata: Sendable {
    let size: Int64
    let fileCount: Int
    let dateModified: Date?
    let dateCreated: Date?
}
