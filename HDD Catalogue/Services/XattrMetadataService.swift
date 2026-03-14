import Foundation

/// Service for reading and writing AI metadata as extended attributes (xattr) on files.
/// This ensures metadata persists with the file itself, surviving database rebuilds
/// and traveling with the file when copied/moved on APFS/HFS+.
///
/// Attribute keys use the prefix `com.hddcatalogue.` to avoid conflicts.
struct XattrMetadataService {
    
    // MARK: - Attribute Keys
    
    private static let prefix = "com.hddcatalogue."
    private static let descriptionKey = prefix + "visualDescription"
    private static let tagsKey        = prefix + "visualTags"
    private static let faceCountKey   = prefix + "faceCount"
    private static let detectedTextKey = prefix + "detectedText"
    
    // MARK: - Data Model
    
    struct XattrMetadata {
        var visualDescription: String?
        var visualTags: [String]?
        var faceCount: Int?
        var detectedText: String?
        
        var hasAnyData: Bool {
            (visualDescription != nil && !visualDescription!.isEmpty) ||
            (visualTags != nil && !visualTags!.isEmpty) ||
            (faceCount != nil && faceCount! > 0) ||
            (detectedText != nil && !detectedText!.isEmpty)
        }
    }
    
    // MARK: - Write
    
    /// Write AI metadata from a MediaFile to the file's extended attributes.
    static func writeMetadata(to url: URL, from file: MediaFile) {
        let path = url.path
        
        if !file.visualDescription.isEmpty {
            setXattr(path: path, key: descriptionKey, value: file.visualDescription)
        }
        
        if !file.visualTags.isEmpty {
            let tagsString = file.visualTags.joined(separator: ",")
            setXattr(path: path, key: tagsKey, value: tagsString)
        }
        
        if file.faceCount > 0 {
            setXattr(path: path, key: faceCountKey, value: String(file.faceCount))
        }
        
        if !file.detectedText.isEmpty {
            // Truncate to keep xattr small
            let truncated = String(file.detectedText.prefix(500))
            setXattr(path: path, key: detectedTextKey, value: truncated)
        }
    }
    
    // MARK: - Read
    
    /// Read AI metadata from a file's extended attributes.
    /// Returns nil if no HDD Catalogue xattrs exist on the file.
    static func readMetadata(from url: URL) -> XattrMetadata? {
        let path = url.path
        
        let description = getXattr(path: path, key: descriptionKey)
        let tagsString = getXattr(path: path, key: tagsKey)
        let faceCountStr = getXattr(path: path, key: faceCountKey)
        let detectedText = getXattr(path: path, key: detectedTextKey)
        
        let tags: [String]? = tagsString.map { str in
            str.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        }
        
        let faceCount: Int? = faceCountStr.flatMap { Int($0) }
        
        let meta = XattrMetadata(
            visualDescription: description,
            visualTags: tags,
            faceCount: faceCount,
            detectedText: detectedText
        )
        
        return meta.hasAnyData ? meta : nil
    }
    
    // MARK: - Low-level xattr helpers
    
    private static func setXattr(path: String, key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            setxattr(path, key, ptr, data.count, 0, 0)
        }
    }
    
    private static func getXattr(path: String, key: String) -> String? {
        // First call to get the size
        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        
        // Second call to get the data
        var buffer = [UInt8](repeating: 0, count: size)
        let result = getxattr(path, key, &buffer, size, 0, 0)
        guard result > 0 else { return nil }
        
        return String(bytes: buffer[0..<result], encoding: .utf8)
    }
}
