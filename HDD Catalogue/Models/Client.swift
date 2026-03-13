import Foundation
import SwiftUI
import SwiftData

@Model
final class Client {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int
    var aiConfidence: Float
    
    @Relationship(deleteRule: .nullify, inverse: \Project.client)
    var projects: [Project] = []
    
    init(
        name: String,
        colorHex: String = ColorPalette.nextColor(),
        sortOrder: Int = 0,
        aiConfidence: Float = 0.0
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.aiConfidence = aiConfidence
    }
    
    var color: Color {
        Color(hex: colorHex) ?? .gray
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        guard hexSanitized.count == 6,
              let hexNumber = UInt64(hexSanitized, radix: 16) else {
            return nil
        }
        
        let r = Double((hexNumber & 0xFF0000) >> 16) / 255.0
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255.0
        let b = Double(hexNumber & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}
