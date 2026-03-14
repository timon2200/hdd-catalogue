import SwiftUI
import SwiftData

/// Sidebar with drives (connected/disconnected), clients, status filters, and tags.
struct SidebarView: View {
    let drives: [Drive]
    let clients: [Client]
    let projects: [Project]
    @Binding var selectedDrive: Drive?
    @Binding var selectedClient: Client?
    @Binding var filterStatus: String
    @Binding var filterTags: Set<String>
    let scanEngine: ScanEngine
    let duplicateCount: Int
    @Binding var showDuplicates: Bool
    let onScanDrive: (Drive) -> Void
    let onScanAll: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(UndoManagerService.self) private var undoService
    @State private var driveToDelete: Drive?
    @State private var clientToDelete: Client?
    @State private var showClientManagement = false
    @State private var showSmartBinEditor = false
    @State private var editingSmartBin: SmartBin?
    @Query(sort: \SmartBin.sortOrder) private var smartBins: [SmartBin]
    let onSelectSmartBin: ((SmartBin?) -> Void)?
    
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
                        .contextMenu {
                            Button("Rescan") { onScanDrive(drive) }
                            Divider()
                            Button("Delete Drive & Projects", role: .destructive) {
                                driveToDelete = drive
                            }
                        }
                }
                
                // Disconnected drives
                ForEach(disconnectedDrives, id: \.id) { drive in
                    driveRow(drive, connected: false)
                        .contextMenu {
                            Button("Delete Drive & Projects", role: .destructive) {
                                driveToDelete = drive
                            }
                        }
                }
            }
            
            // CLIENTS Section
            if !clients.isEmpty {
                Section {
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
                        .contextMenu {
                            Button("Delete Client", role: .destructive) {
                                clientToDelete = client
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Clients")
                        Spacer()
                        Button {
                            showClientManagement = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Manage Clients")
                    }
                }
            }
            
            // SMART BINS Section
            Section {
                ForEach(smartBins, id: \.id) { bin in
                    Button {
                        onSelectSmartBin?(bin)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: bin.icon)
                                .foregroundStyle(.cyan)
                                .frame(width: 16)
                            
                            Text(bin.name)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(bin.matchingProjects(from: projects).count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit") {
                            editingSmartBin = bin
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            modelContext.delete(bin)
                            try? modelContext.save()
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Smart Bins")
                    Spacer()
                    Button {
                        let newBin = SmartBin(name: "")
                        editingSmartBin = newBin
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Create Smart Bin")
                }
            }
            
            // STATUS Section
            Section("Status") {
                ForEach(ProjectStatus.allCases) { status in
                    let count = projects.filter { $0.projectStatus == status }.count
                    Button {
                        if filterStatus == status.rawValue {
                            filterStatus = "All Statuses"
                        } else {
                            filterStatus = status.rawValue
                            selectedDrive = nil
                            selectedClient = nil
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: status.icon)
                                .foregroundStyle(status.color)
                                .frame(width: 16)
                            
                            Text(status.rawValue)
                                .fontWeight(filterStatus == status.rawValue ? .semibold : .regular)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // TAGS Section
            if !allTags.isEmpty {
                Section("Tags") {
                    ForEach(popularTags, id: \.tag) { item in
                        Button {
                            if filterTags.contains(item.tag) {
                                filterTags.remove(item.tag)
                            } else {
                                filterTags.insert(item.tag)
                                selectedDrive = nil
                                selectedClient = nil
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: filterTags.contains(item.tag) ? "tag.fill" : "tag")
                                    .foregroundStyle(tagColor(for: item.tag))
                                    .frame(width: 16)
                                
                                Text(item.tag)
                                    .fontWeight(filterTags.contains(item.tag) ? .semibold : .regular)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text("\(item.count)")
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
                
                // AI Visual Search button
                Button {
                    NotificationCenter.default.post(name: .toggleVisualSearch, object: nil)
                } label: {
                    HStack {
                        Image(systemName: "sparkle.magnifyingglass")
                        Text("AI Visual Search")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.purple)
                .padding(.horizontal, 12)
                
                // Deep Media Search button
                Button {
                    NotificationCenter.default.post(name: .toggleDeepMediaSearch, object: nil)
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Deep Media Search")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                .padding(.horizontal, 12)
                
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
        // Delete Drive confirmation
        .alert("Delete Drive", isPresented: .init(
            get: { driveToDelete != nil },
            set: { if !$0 { driveToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { driveToDelete = nil }
            Button("Delete", role: .destructive) {
                if let drive = driveToDelete {
                    deleteDrive(drive)
                }
            }
        } message: {
            Text("Delete \"\(driveToDelete?.name ?? "")\" and all \(driveToDelete?.projects.count ?? 0) catalogued projects? This does not delete files from disk.")
        }
        // Delete Client confirmation
        .alert("Delete Client", isPresented: .init(
            get: { clientToDelete != nil },
            set: { if !$0 { clientToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { clientToDelete = nil }
            Button("Delete", role: .destructive) {
                if let client = clientToDelete {
                    deleteClient(client)
                }
            }
        } message: {
            Text("Delete client \"\(clientToDelete?.name ?? "")\"? Projects will become uncategorized.")
        }
        .sheet(isPresented: $showClientManagement) {
            ClientManagementView()
        }
        .sheet(item: $editingSmartBin) { bin in
            SmartBinEditorView(
                smartBin: bin,
                isNew: bin.name.isEmpty
            )
        }
    }
    
    // MARK: - Actions
    
    private func deleteDrive(_ drive: Drive) {
        if selectedDrive?.id == drive.id { selectedDrive = nil }
        let projects = drive.projects
        undoService.registerDriveDeletion(drive: drive, projects: projects, context: modelContext)
        modelContext.delete(drive)
        try? modelContext.save()
    }
    
    private func deleteClient(_ client: Client) {
        if selectedClient?.id == client.id { selectedClient = nil }
        let projectIds = client.projects.map(\.id)
        undoService.registerClientDeletion(client: client, projectIds: projectIds, context: modelContext)
        modelContext.delete(client)
        try? modelContext.save()
    }
    
    // MARK: - Drive Row
    
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
    
    // MARK: - Tags Helpers
    
    private var allTags: [String] {
        Array(Set(projects.flatMap(\.tags)))
    }
    
    private struct TagItem {
        let tag: String
        let count: Int
    }
    
    private var popularTags: [TagItem] {
        var tagCounts: [String: Int] = [:]
        for project in projects {
            for tag in project.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return tagCounts
            .map { TagItem(tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(10)
            .map { $0 }
    }
    
    private func tagColor(for tag: String) -> Color {
        let hash = abs(tag.hashValue)
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan]
        return colors[hash % colors.count]
    }
}

