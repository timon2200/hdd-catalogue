import SwiftUI

/// Sidebar with drives (connected/disconnected) and clients with color dots.
struct SidebarView: View {
    let drives: [Drive]
    let clients: [Client]
    @Binding var selectedDrive: Drive?
    @Binding var selectedClient: Client?
    let scanEngine: ScanEngine
    let duplicateCount: Int
    @Binding var showDuplicates: Bool
    let onScanDrive: (Drive) -> Void
    let onScanAll: () -> Void
    
    var connectedDrives: [Drive] {
        drives.filter(\.isConnected)
    }
    
    var disconnectedDrives: [Drive] {
        drives.filter { !$0.isConnected }
    }
    
    var body: some View {
        List {
            // DRIVES Section
            Section("Drives") {
                // All Drives filter
                Button {
                    selectedDrive = nil
                    selectedClient = nil
                } label: {
                    Label {
                        Text("All Drives")
                            .fontWeight(selectedDrive == nil && selectedClient == nil ? .semibold : .regular)
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
                
                // Connected drives
                ForEach(connectedDrives, id: \.id) { drive in
                    driveRow(drive, connected: true)
                }
                
                // Disconnected drives
                ForEach(disconnectedDrives, id: \.id) { drive in
                    driveRow(drive, connected: false)
                }
            }
            
            // CLIENTS Section
            if !clients.isEmpty {
                Section("Clients") {
                    ForEach(clients.sorted(by: { $0.name < $1.name }), id: \.id) { client in
                        Button {
                            if selectedClient?.id == client.id {
                                selectedClient = nil
                            } else {
                                selectedClient = client
                                selectedDrive = nil
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(client.color)
                                    .frame(width: 10, height: 10)
                                
                                Text(client.name)
                                    .fontWeight(selectedClient?.id == client.id ? .semibold : .regular)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text("\(client.projects.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // ALERTS Section
            if duplicateCount > 0 {
                Section("Alerts") {
                    Button {
                        showDuplicates = true
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Duplicates Found")
                            Spacer()
                            Text("\(duplicateCount)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange, in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Divider()
                
                Button {
                    onScanAll()
                } label: {
                    HStack {
                        if scanEngine.isScanning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning…")
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Scan All Drives")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanEngine.isScanning || connectedDrives.isEmpty)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .background(.ultraThinMaterial)
        }
    }
    
    @ViewBuilder
    private func driveRow(_ drive: Drive, connected: Bool) -> some View {
        Button {
            if selectedDrive?.id == drive.id {
                selectedDrive = nil
            } else {
                selectedDrive = drive
                selectedClient = nil
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Image(systemName: connected ? "externaldrive.fill" : "externaldrive")
                        .font(.title3)
                        .foregroundStyle(connected ? .blue : .gray)
                    
                    if !connected {
                        Image(systemName: "eject.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .offset(x: 8, y: 8)
                    }
                }
                .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(drive.name)
                        .fontWeight(selectedDrive?.id == drive.id ? .semibold : .regular)
                        .opacity(connected ? 1.0 : 0.5)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(drive.formattedCapacity)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        if connected {
                            // Capacity bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.quaternary)
                                    Capsule()
                                        .fill(drive.usagePercentage > 0.9 ? .red : .blue)
                                        .frame(width: geo.size.width * drive.usagePercentage)
                                }
                                .frame(height: 4)
                            }
                            .frame(height: 4)
                        }
                    }
                }
                
                Spacer()
                
                if connected && !scanEngine.isScanning {
                    Button {
                        onScanDrive(drive)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rescan drive")
                }
            }
        }
        .buttonStyle(.plain)
    }
}
