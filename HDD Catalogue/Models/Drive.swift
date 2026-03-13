import Foundation
import SwiftData

@Model
final class Drive {
    @Attribute(.unique) var id: UUID
    var name: String
    var volumePath: String
    var serialNumber: String
    var totalCapacityBytes: Int64
    var availableCapacityBytes: Int64
    var lastScanned: Date?
    var driveType: String // "HDD", "SSD", "USB", "Unknown"
    var isConnected: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \Project.drive)
    var projects: [Project] = []
    
    init(
        name: String,
        volumePath: String,
        serialNumber: String = "",
        totalCapacityBytes: Int64 = 0,
        availableCapacityBytes: Int64 = 0,
        driveType: String = "Unknown",
        isConnected: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.volumePath = volumePath
        self.serialNumber = serialNumber
        self.totalCapacityBytes = totalCapacityBytes
        self.availableCapacityBytes = availableCapacityBytes
        self.driveType = driveType
        self.isConnected = isConnected
    }
    
    var formattedCapacity: String {
        ByteCountFormatter.string(fromByteCount: totalCapacityBytes, countStyle: .file)
    }
    
    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableCapacityBytes, countStyle: .file)
    }
    
    var usagePercentage: Double {
        guard totalCapacityBytes > 0 else { return 0 }
        return Double(totalCapacityBytes - availableCapacityBytes) / Double(totalCapacityBytes)
    }
}
