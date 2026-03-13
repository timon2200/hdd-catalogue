import Foundation
import SwiftData
import AppKit
import Combine

/// Monitors external drive mount/unmount events and maintains drive state.
@Observable @MainActor
final class DriveMonitor {
    var connectedDrives: [URL] = []
    var isScanning: Bool = false
    
    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?
    private var modelContext: ModelContext?
    private var scanEngine: ScanEngine?
    private var onDriveMounted: ((Drive) -> Void)?
    private var isMonitoring = false
    
    init() {
        refreshConnectedDrives()
    }
    
    /// Start monitoring with a model context for persistence.
    func startMonitoring(
        modelContext: ModelContext,
        scanEngine: ScanEngine,
        onDriveMounted: @escaping (Drive) -> Void
    ) {
        // Prevent duplicate monitoring setup
        guard !isMonitoring else { return }
        isMonitoring = true
        
        self.modelContext = modelContext
        self.scanEngine = scanEngine
        self.onDriveMounted = onDriveMounted
        
        // Mark all existing drives as disconnected initially
        markAllDrivesDisconnected()
        
        // Then check what's currently mounted
        refreshConnectedDrives()
        syncConnectedDrives()
        
        // Listen for mount events
        mountObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let path = url.path
            let name = url.lastPathComponent
            Task { @MainActor in
                self?.handleMount(volumeURL: url, volumePath: path, volumeName: name)
            }
        }
        
        // Listen for unmount events
        unmountObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            let path = url.path
            Task { @MainActor in
                self?.handleUnmount(volumePath: path)
            }
        }
    }
    
    func stopMonitoring() {
        if let observer = mountObserver {
            NotificationCenter.default.removeObserver(observer)
            mountObserver = nil
        }
        if let observer = unmountObserver {
            NotificationCenter.default.removeObserver(observer)
            unmountObserver = nil
        }
        isMonitoring = false
    }
    
    // MARK: - Private
    
    private func refreshConnectedDrives() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]
        
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return }
        
        connectedDrives = volumes.filter { url in
            // Accept everything mounted under /Volumes (except the boot volume)
            let path = url.path
            if path == "/" { return false }
            if path.hasPrefix("/Volumes/") { return true }
            
            // Fallback: check volume properties
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            let isInternal = values.volumeIsInternal ?? true
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false
            
            return !isInternal || isRemovable || isEjectable
        }
    }
    
    private func markAllDrivesDisconnected() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<Drive>()
        guard let drives = try? context.fetch(descriptor) else { return }
        for drive in drives {
            drive.isConnected = false
        }
        try? context.save()
    }
    
    private func syncConnectedDrives() {
        guard let context = modelContext else { return }
        
        for volumeURL in connectedDrives {
            let volumePath = volumeURL.path
            let volumeName = volumeURL.lastPathComponent
            
            // Check if drive already exists in database
            let descriptor = FetchDescriptor<Drive>(
                predicate: #Predicate<Drive> { $0.volumePath == volumePath }
            )
            
            if let existingDrive = try? context.fetch(descriptor).first {
                existingDrive.isConnected = true
                updateDriveCapacity(existingDrive, from: volumeURL)
            } else {
                // Create new drive entry
                let drive = createDrive(from: volumeURL, name: volumeName, path: volumePath)
                context.insert(drive)
                
                // Trigger auto-scan for new drives
                onDriveMounted?(drive)
            }
        }
        
        try? context.save()
    }
    
    private func handleMount(volumeURL: URL, volumePath: String, volumeName: String) {
        guard let context = modelContext else { return }
        
        refreshConnectedDrives()
        
        // Check if this drive was previously catalogued
        let descriptor = FetchDescriptor<Drive>(
            predicate: #Predicate<Drive> { $0.volumePath == volumePath }
        )
        
        if let existingDrive = try? context.fetch(descriptor).first {
            existingDrive.isConnected = true
            updateDriveCapacity(existingDrive, from: volumeURL)
            try? context.save()
            
            // Re-scan existing drive for changes
            onDriveMounted?(existingDrive)
        } else {
            // Brand new drive
            let drive = createDrive(from: volumeURL, name: volumeName, path: volumePath)
            context.insert(drive)
            try? context.save()
            
            onDriveMounted?(drive)
        }
    }
    
    private func handleUnmount(volumePath: String) {
        guard let context = modelContext else { return }
        
        refreshConnectedDrives()
        
        let descriptor = FetchDescriptor<Drive>(
            predicate: #Predicate<Drive> { $0.volumePath == volumePath }
        )
        
        if let drive = try? context.fetch(descriptor).first {
            drive.isConnected = false
            try? context.save()
        }
    }
    
    private func createDrive(from url: URL, name: String, path: String) -> Drive {
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ])
        
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let available = Int64(values?.volumeAvailableCapacity ?? 0)
        
        let driveType = detectDriveType(for: url)
        
        return Drive(
            name: name,
            volumePath: path,
            serialNumber: getSerialNumber(for: url),
            totalCapacityBytes: total,
            availableCapacityBytes: available,
            driveType: driveType,
            isConnected: true
        )
    }
    
    private func updateDriveCapacity(_ drive: Drive, from url: URL) {
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ])
        drive.totalCapacityBytes = Int64(values?.volumeTotalCapacity ?? 0)
        drive.availableCapacityBytes = Int64(values?.volumeAvailableCapacity ?? 0)
    }
    
    private nonisolated func getSerialNumber(for url: URL) -> String {
        let path = url.path
        return "\(path.hashValue)"
    }
    
    private nonisolated func detectDriveType(for url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("ssd") {
            return "SSD"
        } else if path.contains("usb") || path.contains("flash") {
            return "USB"
        }
        return "HDD"
    }
}
