import SwiftUI
import SwiftData

/// Grid of project cards with client legend, search, and sort controls.
struct CatalogueGridView: View {
    let projects: [Project]
    let clients: [Client]
    @Binding var searchText: String
    @Binding var selectedClient: Client?
    let isAIProcessing: Bool
    
    @State private var editingProject: Project?
    @State private var showThumbnailPicker: Project?
    @State private var viewMode: ViewMode = .grid
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
    }
    
    private let gridColumns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Client legend bar
            if !clients.isEmpty {
                clientLegendBar
            }
            
            // Content
            if projects.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    switch viewMode {
                    case .grid:
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(projects, id: \.id) { project in
                                ProjectCardView(
                                    project: project,
                                    onEdit: { editingProject = project },
                                    onChangeThumbnail: { showThumbnailPicker = project }
                                )
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }
                        .padding(20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: projects.count)
                        
                    case .list:
                        LazyVStack(spacing: 2) {
                            ForEach(projects, id: \.id) { project in
                                projectListRow(project)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
            
            // Status bar
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("View", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2")
                        .tag(ViewMode.grid)
                    Image(systemName: "list.bullet")
                        .tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .help("Toggle grid/list view")
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditView(project: project)
        }
        .sheet(item: $showThumbnailPicker) { project in
            ThumbnailPickerView(project: project)
        }
    }
    
    // MARK: - Client Legend
    
    private var clientLegendBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(clients.sorted(by: { $0.projects.count > $1.projects.count }), id: \.id) { client in
                    Button {
                        if selectedClient?.id == client.id {
                            selectedClient = nil
                        } else {
                            selectedClient = client
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(client.color)
                                .frame(width: 8, height: 8)
                            Text(client.name)
                                .font(.caption)
                                .fontWeight(selectedClient?.id == client.id ? .bold : .regular)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selectedClient?.id == client.id
                            ? client.color.opacity(0.2)
                            : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedClient?.id == client.id ? client.color.opacity(0.5) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            
            Text("No Projects Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            if searchText.isEmpty {
                Text("Connect an external drive to get started.\nProjects will be automatically indexed when you plug in a drive.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            } else {
                Text("No projects match \"\(searchText)\"")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            if isAIProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI is analyzing your projects…")
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - List Row
    
    @ViewBuilder
    private func projectListRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            projectThumbnail(project)
                .frame(width: 32, height: 32)
            
            // Client color accent
            RoundedRectangle(cornerRadius: 2)
                .fill(project.client?.color ?? .gray)
                .frame(width: 3, height: 28)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let clientName = project.client?.name {
                        Text(clientName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(project.projectType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Drive info
            if let drive = project.drive {
                HStack(spacing: 4) {
                    Image(systemName: drive.isConnected ? "externaldrive.fill" : "externaldrive")
                        .font(.caption2)
                        .foregroundStyle(drive.isConnected ? .green : .gray)
                    Text(drive.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .opacity(drive.isConnected ? 1.0 : 0.5)
            }
            
            Text(project.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            
            Text(project.formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            projectContextMenu(project)
        }
    }
    
    @ViewBuilder
    private func projectThumbnail(_ project: Project) -> some View {
        switch project.thumbnailType {
        case .image:
            if let data = project.thumbnailData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                defaultThumbnail(project)
            }
        case .emoji:
            Text(project.resolvedThumbnailEmoji)
                .font(.title2)
        case .icon:
            Image(systemName: project.thumbnailIconName ?? ThumbnailManager.defaultSFSymbol(for: project.projectType))
                .font(.title2)
                .foregroundStyle(project.client?.color ?? .gray)
        case .auto:
            Text(project.autoThumbnailEmoji)
                .font(.title2)
        }
    }
    
    @ViewBuilder
    private func defaultThumbnail(_ project: Project) -> some View {
        Text(project.autoThumbnailEmoji)
            .font(.title2)
    }
    
    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        Button("Edit Project") { editingProject = project }
        Button("Change Thumbnail") { showThumbnailPicker = project }
        Divider()
        if let path = project.drive?.isConnected == true ? project.folderPath : nil {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            }
        }
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            let drives = Set(projects.compactMap(\.drive?.id))
            let clientCount = Set(projects.compactMap(\.client?.id)).count
            
            Text("\(projects.count) projects · \(clientCount) clients · \(drives.count) drives")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if isAIProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("AI processing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
