import SwiftUI

/// Shared deterministic tag color helper — used across sidebar, cards, tag input, and drawer.
enum TagColorHelper {
    /// Returns a consistent color for a given tag string based on its hash.
    static func color(for tag: String) -> Color {
        let hash = abs(tag.hashValue)
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan]
        return palette[hash % palette.count]
    }
}
