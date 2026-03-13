import Foundation
import SwiftUI

/// A curated palette of 20 visually distinct colors for client assignment.
enum ColorPalette {
    static let colors: [String] = [
        "#4A9EFF", // Bright Blue
        "#FF6B6B", // Coral Red
        "#50C878", // Emerald Green
        "#FFB347", // Tangerine Orange
        "#9B59B6", // Amethyst Purple
        "#1ABC9C", // Turquoise
        "#E74C8B", // Hot Pink
        "#F39C12", // Sunflower Yellow
        "#3498DB", // Sky Blue
        "#2ECC71", // Mint Green
        "#E67E22", // Carrot Orange
        "#8E44AD", // Deep Purple
        "#16A085", // Dark Turquoise
        "#C0392B", // Pomegranate Red
        "#2980B9", // Steel Blue
        "#27AE60", // Forest Green
        "#D35400", // Pumpkin
        "#7F8C8D", // Concrete Gray
        "#F1C40F", // Bright Yellow
        "#E91E63", // Material Pink
    ]
    
    private static var colorIndex = 0
    
    /// Returns the next color from the palette in sequence.
    static func nextColor() -> String {
        let color = colors[colorIndex % colors.count]
        colorIndex += 1
        return color
    }
    
    /// Returns a color for a given index.
    static func color(at index: Int) -> String {
        colors[index % colors.count]
    }
    
    /// Resets the color assignment counter.
    static func reset() {
        colorIndex = 0
    }
    
    /// Returns a SwiftUI Color for the given hex string.
    static func swiftUIColor(for hex: String) -> Color {
        Color(hex: hex) ?? .gray
    }
}
