import Foundation
import AppKit
import SwiftUI

/// Manages project thumbnails — image drops, emoji search, SF Symbol selection.
enum ThumbnailManager {
    
    /// Process a dropped image and return resized thumbnail data.
    static func processDroppedImage(_ data: Data, maxSize: CGFloat = 128) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        return resizeImage(image, maxSize: maxSize)
    }
    
    /// Process an image file URL and return resized thumbnail data.
    static func processImageFile(_ url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return resizeImage(image, maxSize: 128)
    }
    
    /// Resize an NSImage to fit within maxSize while maintaining aspect ratio.
    static func resizeImage(_ image: NSImage, maxSize: CGFloat) -> Data? {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }
        
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height, 1.0)
        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        
        guard let tiffData = newImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return pngData
    }
    
    // MARK: - Emoji Categories
    
    /// Common emoji categories for project thumbnails.
    static let emojiCategories: [(name: String, emojis: [String])] = [
        ("Work", ["💼", "📋", "📁", "🗂️", "📂", "💻", "🖥️", "⌨️", "🖱️", "📊"]),
        ("Creative", ["🎨", "✏️", "🖌️", "🎬", "📸", "🎵", "🎤", "🎭", "🎪", "🌈"]),
        ("Web & Dev", ["🌐", "💻", "📱", "⚙️", "🔧", "🛠️", "📡", "🔌", "💾", "🖥️"]),
        ("Media", ["📷", "🎥", "📹", "🎞️", "📺", "📻", "🎙️", "🔊", "🎶", "🎼"]),
        ("Documents", ["📝", "📄", "📑", "📃", "📰", "📓", "📔", "📚", "📖", "✍️"]),
        ("Business", ["🏢", "🏗️", "🏭", "🏪", "💰", "💳", "📈", "📉", "🤝", "👔"]),
        ("Nature", ["🌿", "🌸", "🌺", "🌻", "🌲", "🏔️", "🌊", "☀️", "🌙", "⭐"]),
        ("Objects", ["🏠", "🚀", "✈️", "🚗", "⛵", "🎯", "🏆", "💎", "🔑", "🎁"]),
    ]
    
    /// Search emojis by keyword.
    static func searchEmojis(_ query: String) -> [String] {
        if query.isEmpty {
            return emojiCategories.flatMap(\.emojis)
        }
        
        let lowered = query.lowercased()
        return emojiCategories
            .filter { $0.name.lowercased().contains(lowered) }
            .flatMap(\.emojis)
    }
    
    // MARK: - SF Symbol Categories
    
    /// Curated SF Symbols useful for project thumbnails.
    static let sfSymbolCategories: [(name: String, symbols: [String])] = [
        ("Folders", ["folder.fill", "folder.badge.gearshape", "folder.badge.plus", "folder.badge.person.crop", "archivebox.fill"]),
        ("Media", ["photo.fill", "video.fill", "film", "camera.fill", "music.note", "waveform"]),
        ("Code", ["chevron.left.forwardslash.chevron.right", "terminal.fill", "cpu", "memorychip", "externaldrive.fill"]),
        ("Design", ["paintbrush.fill", "pencil.tip.crop.circle", "scribble.variable", "lasso", "wand.and.stars"]),
        ("Web", ["globe", "network", "antenna.radiowaves.left.and.right", "wifi", "link"]),
        ("Documents", ["doc.fill", "doc.text.fill", "book.fill", "newspaper.fill", "text.alignleft"]),
        ("Business", ["building.2.fill", "briefcase.fill", "chart.bar.fill", "dollarsign.circle.fill", "person.2.fill"]),
        ("Tools", ["wrench.and.screwdriver.fill", "gearshape.fill", "hammer.fill", "slider.horizontal.3", "tuningfork"]),
    ]
    
    /// Returns the default SF Symbol based on project type.
    static func defaultSFSymbol(for projectType: String) -> String {
        switch projectType.lowercased() {
        case let t where t.contains("web"):
            return "globe"
        case let t where t.contains("video") || t.contains("motion"):
            return "video.fill"
        case let t where t.contains("photo"):
            return "camera.fill"
        case let t where t.contains("3d") || t.contains("render"):
            return "cube.fill"
        case let t where t.contains("dev") || t.contains("code") || t.contains("software"):
            return "chevron.left.forwardslash.chevron.right"
        case let t where t.contains("music") || t.contains("audio"):
            return "music.note"
        case let t where t.contains("brand") || t.contains("logo"):
            return "paintbrush.fill"
        case let t where t.contains("document"):
            return "doc.text.fill"
        default:
            return "folder.fill"
        }
    }
}
