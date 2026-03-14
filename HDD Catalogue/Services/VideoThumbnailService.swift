import Foundation
import AVFoundation
import AppKit

/// Extracts video frame thumbnails from project folders using AVFoundation.
enum VideoThumbnailService {
    
    /// Video file extensions eligible for thumbnail extraction.
    static let videoExtensions: Set<String> = ["mp4", "mov", "mxf", "m4v"]
    
    /// Find the first video file in a project's export folder (preferred) or root.
    /// Searches export folders first for "final" looking content, then falls back to any video.
    static func findVideoFile(in projectURL: URL) -> URL? {
        let fm = FileManager.default
        
        // First, try export/render folders for a "hero" video
        let exportFolderNames = NLEDetector.exportFolderNames
        if let contents = try? fm.contentsOfDirectory(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for dir in contents {
                let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                
                if exportFolderNames.contains(dir.lastPathComponent.lowercased()) {
                    if let video = firstVideoInDirectory(dir) {
                        return video
                    }
                }
            }
        }
        
        // Fall back: find first video anywhere in project (limit depth to 3)
        return firstVideoInDirectory(projectURL, maxDepth: 3)
    }
    
    /// Extract a frame from a video at ~10% of its duration.
    static func extractFrame(from videoURL: URL, maxSize: CGFloat = 200) async -> Data? {
        let asset = AVAsset(url: videoURL)
        
        guard let duration = try? await asset.load(.duration),
              duration.seconds > 0 else {
            return nil
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize * 2, height: maxSize * 2)
        
        // Grab frame at 10% of duration
        let timestamp = CMTime(
            seconds: duration.seconds * 0.1,
            preferredTimescale: duration.timescale
        )
        
        do {
            let (cgImage, _) = try await generator.image(at: timestamp)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                width: cgImage.width,
                height: cgImage.height
            ))
            return ThumbnailManager.resizeImage(nsImage, maxSize: maxSize)
        } catch {
            return nil
        }
    }
    
    /// Convenience: find a video in the project and extract a thumbnail.
    static func generateThumbnail(for projectURL: URL) async -> Data? {
        guard let videoURL = findVideoFile(in: projectURL) else { return nil }
        return await extractFrame(from: videoURL, maxSize: 400)
    }
    
    // MARK: - Private
    
    /// Finds the first video file in a directory, optionally limited by depth.
    private static func firstVideoInDirectory(_ url: URL, maxDepth: Int = 1, currentDepth: Int = 0) -> URL? {
        guard currentDepth < maxDepth else { return nil }
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        
        // Check files first
        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir {
                let ext = item.pathExtension.lowercased()
                if videoExtensions.contains(ext) {
                    return item
                }
            }
        }
        
        // Then recurse into subdirectories
        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if let found = firstVideoInDirectory(item, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                    return found
                }
            }
        }
        
        return nil
    }
}
