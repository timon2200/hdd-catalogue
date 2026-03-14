import Foundation

/// Breakdown of media file types found within a project folder.
struct MediaSummary: Codable, Sendable, Equatable {
    var videoCount: Int = 0
    var audioCount: Int = 0
    var graphicsCount: Int = 0
    var fontCount: Int = 0
    var renderCount: Int = 0
    
    var totalCount: Int {
        videoCount + audioCount + graphicsCount + fontCount + renderCount
    }
    
    var isEmpty: Bool { totalCount == 0 }
    
    /// Returns the dominant media category name, or "Mixed" if tied.
    var dominantType: String {
        let counts = [
            ("Video", videoCount),
            ("Audio", audioCount),
            ("Graphics", graphicsCount),
            ("Fonts", fontCount),
            ("Renders", renderCount),
        ]
        guard let max = counts.max(by: { $0.1 < $1.1 }), max.1 > 0 else {
            return "Unknown"
        }
        return max.0
    }
    
    // MARK: - File Extension Mapping
    
    /// Video file extensions.
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "mxf", "r3d", "braw", "ari", "mkv", "avi", "wmv", "m4v", "prores"
    ]
    
    /// Audio file extensions.
    static let audioExtensions: Set<String> = [
        "wav", "mp3", "aac", "aif", "aiff", "flac", "ogg", "m4a", "wma"
    ]
    
    /// Graphics / image file extensions.
    static let graphicsExtensions: Set<String> = [
        "psd", "ai", "png", "svg", "mogrt", "jpg", "jpeg", "tiff", "tif",
        "gif", "bmp", "webp", "exr", "dpx", "eps", "indd", "afdesign"
    ]
    
    /// Font file extensions.
    static let fontExtensions: Set<String> = [
        "ttf", "otf", "woff", "woff2"
    ]
    
    /// Classify a file extension into a media category.
    static func category(for ext: String) -> MediaCategory? {
        let lower = ext.lowercased()
        if videoExtensions.contains(lower) { return .video }
        if audioExtensions.contains(lower) { return .audio }
        if graphicsExtensions.contains(lower) { return .graphics }
        if fontExtensions.contains(lower) { return .font }
        return nil
    }
    
    enum MediaCategory {
        case video, audio, graphics, font, render
    }
}

// MARK: - NLE Detection Helpers

/// Maps NLE project file extensions to application names.
enum NLEDetector {
    
    /// Known NLE project file extensions → application name.
    static let nleExtensions: [String: String] = [
        "prproj":    "Premiere Pro",
        "fcpbundle": "Final Cut Pro",
        "fcpxml":    "Final Cut Pro",
        "drp":       "DaVinci Resolve",
        "aep":       "After Effects",
        "sesx":      "Adobe Audition",
        "mogrt":     "Motion Graphics",
    ]
    
    /// SF Symbol name for each NLE.
    static func sfSymbol(for nle: String) -> String {
        switch nle {
        case "Premiere Pro":     return "film"
        case "Final Cut Pro":    return "film.stack"
        case "DaVinci Resolve":  return "paintpalette"
        case "After Effects":    return "sparkles.rectangle.stack"
        case "Adobe Audition":   return "waveform"
        case "Motion Graphics":  return "rectangle.stack.badge.play"
        default:                 return "play.rectangle"
        }
    }
    
    /// Short abbreviation for badge display.
    static func abbreviation(for nle: String) -> String {
        switch nle {
        case "Premiere Pro":     return "Pr"
        case "Final Cut Pro":    return "FCP"
        case "DaVinci Resolve":  return "DVR"
        case "After Effects":    return "Ae"
        case "Adobe Audition":   return "Au"
        case "Motion Graphics":  return "MoGRT"
        default:                 return "NLE"
        }
    }
    
    /// Known camera model folder name patterns.
    static let knownCameraPatterns: [String] = [
        "ZV-E1", "ZV-E10", "ZV-1",
        "A7IV", "A7III", "A7S", "A7SII", "A7SIII", "A7RIV", "A7RV", "A7C", "A6700", "A6600", "A6400",
        "FX3", "FX6", "FX30",
        "Pocket", "BMPCC", "BMPCC4K", "BMPCC6K",
        "GH5", "GH6", "GH5S", "S1H", "S5",
        "R5", "R6", "R3", "C70", "C300", "C500",
        "RED", "DSMC",
    ]
    
    /// Drone-related folder name patterns.
    static let dronePatterns: [String] = [
        "Mavic", "DJI", "FPV", "Mini", "Phantom", "Air", "Inspire",
        "Mavic 4 Pro", "Mavic 3", "Mini 4 Pro", "Mini 3 Pro",
    ]
    
    /// Export/render folder names (case-insensitive match).
    static let exportFolderNames: Set<String> = [
        "renders", "exports", "deliverables", "output", "delivery", "final",
        "render", "export", "deliverable",
    ]
    
    /// Production/shoot-day folder patterns (Croatian and English).
    static let shootDayPatterns: [String] = [
        "proizvodnja", "shoot day", "shoot", "day", "dan", "dodatno", "snimanje",
    ]
}
