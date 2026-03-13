import SwiftUI
import SwiftData

/// Menu bar dropdown view showing connected drives and quick actions.
struct MenuBarView: View {
    let driveMonitor: DriveMonitor
    let scanEngine: ScanEngine
    @Binding var showMainWindow: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var drives: [Drive]
    @Query private var projects: [Project]
    @Query private var clients: [Client]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.blue)
                Text("HDD Catalogue")
                    .font(.headline)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            
            Divider()
            
            // Connected Drives
            let connectedDrives = drives.filter(\.isConnected)
            let disconnectedDrives = drives.filter { !$0.isConnected }
            
            if !connectedDrives.isEmpty {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                
                ForEach(connectedDrives, id: \.id) { drive in
                    driveRow(drive, connected: true)
                }
            }
            
            if !disconnectedDrives.isEmpty {
                Text("Offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                
                ForEach(disconnectedDrives.prefix(5), id: \.id) { drive in
                    driveRow(drive, connected: false)
                }
            }
            
            if drives.isEmpty {
                Text("No drives catalogued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
            
            Divider()
            
            // Stats
            HStack(spacing: 12) {
                Label("\(projects.count)", systemImage: "folder.fill")
                Label("\(clients.count)", systemImage: "person.2.fill")
                Label("\(drives.count)", systemImage: "externaldrive.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            
            Divider()
            
            // Actions
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            
            Button("Open Catalogue") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")
            
            Divider()
            
            Button("Quit HDD Catalogue") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func driveRow(_ drive: Drive, connected: Bool) -> some View {
        HStack {
            Image(systemName: connected ? "externaldrive.fill" : "externaldrive")
                .foregroundStyle(connected ? .green : .gray)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(drive.name)
                    .font(.caption)
                    .opacity(connected ? 1 : 0.6)
                
                Text("\(drive.formattedCapacity)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if scanEngine.isScanning {
                ProgressView()
                    .controlSize(.mini)
            }
            
            Text("\(drive.projects.count) projects")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}
