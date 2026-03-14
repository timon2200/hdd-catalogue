import SwiftUI
import SwiftData

/// Grid of project cards with client legend, search, sort controls, and Phase 1 NLE filtering.
struct CatalogueGridView: View {
    let projects: [Project]
    let allProjects: [Project]  // All projects for file-level search
    let clients: [Client]
    @Binding var searchText: String
    @Binding var selectedClient: Client?
    let isAIProcessing: Bool
    
    // Advanced filter bindings
    @Binding var showFilters: Bool
    @Binding var filterType: String
    @Binding var filterDateFrom: Date?
    @Binding var filterDateTo: Date?
    @Binding var filterMinSize: Int64
    @Binding var filterNLE: String
    @Binding var filterStatus: String
    @Binding var filterTags: Set<String>
    var showDashboard: Bool = false
    @Binding var selectedProject: Project?
    @Binding var explorerProject: Project?
    @Binding var explorerInitialFile: String?
    
    @State private var showThumbnailPicker: Project?
    @State private var projectToDelete: Project?
    @State private var viewMode: ViewMode = .grid
    @State private var sortBy: SortOption = .date
    @State private var sortAscending: Bool = false
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
    }
    
    enum SortOption: String, CaseIterable {
        case date = "Date"
        case name = "Name"
        case size = "Size"
        case client = "Client"
        case status = "Status"
        case completeness = "Completeness"
        
        var icon: String {
            switch self {
            case .date: return "calendar"
            case .name: return "textformat.abc"
            case .size: return "externaldrive"
            case .client: return "person.2"
            case .status: return "circle.lefthalf.filled"
            case .completeness: return "chart.pie"
            }
        }
    }
    
    private let gridColumns = [
        GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)
    ]
    
    /// Projects sorted by user's chosen criteria, with favorites pinned to top.
    private var sortedProjects: [Project] {
        let sorted: [Project]
        switch sortBy {
        case .date:
            sorted = projects.sorted {
                let d0 = $0.projectDate ?? .distantPast
                let d1 = $1.projectDate ?? .distantPast
                return sortAscending ? d0 < d1 : d0 > d1
            }
        case .name:
            sorted = projects.sorted {
                sortAscending
                    ? $0.displayName.localizedCompare($1.displayName) == .orderedAscending
                    : $0.displayName.localizedCompare($1.displayName) == .orderedDescending
            }
        case .size:
            sorted = projects.sorted {
                sortAscending ? $0.sizeBytes < $1.sizeBytes : $0.sizeBytes > $1.sizeBytes
            }
        case .client:
            sorted = projects.sorted {
                let c0 = $0.client?.name ?? "zzz"
                let c1 = $1.client?.name ?? "zzz"
                return sortAscending ? c0 < c1 : c0 > c1
            }
        case .status:
            let order: [ProjectStatus] = [.new, .inProgress, .review, .delivered, .archived]
            sorted = projects.sorted {
                let i0 = order.firstIndex(of: $0.projectStatus) ?? 0
                let i1 = order.firstIndex(of: $1.projectStatus) ?? 0
                return sortAscending ? i0 < i1 : i0 > i1
            }
        case .completeness:
            sorted = projects.sorted {
                sortAscending
                    ? $0.projectCompleteness < $1.projectCompleteness
                    : $0.projectCompleteness > $1.projectCompleteness
            }
        }
        
        // Pin favorites to the top
        let favorites = sorted.filter(\.isFavorite)
        let rest = sorted.filter { !$0.isFavorite }
        return favorites + rest
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Client legend bar
            if !clients.isEmpty {
                clientLegendBar
            }
            
            // Advanced filter bar
            if showFilters {
                filterBar
            }
            
            // Content
            ScrollView {
                if sortedProjects.isEmpty && searchText.isEmpty {
                    emptyStateView
                } else if !sortedProjects.isEmpty {
                    // Dashboard stats header
                    if showDashboard {
                        dashboardHeader
                    }
                    
                    switch viewMode {
                    case .grid:
                        if showDashboard {
                            groupedGridView
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(sortedProjects, id: \.id) { project in
                                    ProjectCardView(
                                        project: project,
                                        onEdit: { selectedProject = project },
                                        onChangeThumbnail: { showThumbnailPicker = project },
                                        onShowDetail: { selectedProject = project },
                                        onOpenExplorer: { explorerProject = project }
                                    )
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }
                            }
                            .padding(20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: projects.count)
                        }
                        
                    case .list:
                        LazyVStack(spacing: 2) {
                            ForEach(sortedProjects, id: \.id) { project in
                                projectListRow(project)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
                
                // File-level search results (searches ALL projects)
                if !searchText.isEmpty {
                    let fileMatches = matchingFiles
                    if !fileMatches.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.cyan)
                                Text("Matching Files")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text("(\(fileMatches.count)\(fileMatches.count >= 50 ? "+" : ""))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            
                            LazyVStack(spacing: 1) {
                                ForEach(fileMatches) { match in
                                    fileResultRow(match)
                                }
                            }
                            .background(
                                Color(red: 0.1, green: 0.12, blue: 0.15).opacity(0.5),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        }
                    } else if projects.isEmpty {
                        // No projects AND no files matched
                        VStack(spacing: 12) {
                            Spacer(minLength: 60)
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No results for \"\(searchText)\"")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("No projects or files match your search")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 60)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            
            // Status bar
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    // Sort controls
                    Menu {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                if sortBy == option {
                                    sortAscending.toggle()
                                } else {
                                    sortBy = option
                                    sortAscending = option == .name
                                }
                            } label: {
                                HStack {
                                    Image(systemName: option.icon)
                                    Text(option.rawValue)
                                    if sortBy == option {
                                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 11))
                            Text(sortBy.rawValue)
                                .font(.system(size: 11))
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Sort projects")
                    
                    // View toggle
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
        }
        .sheet(item: $showThumbnailPicker) { project in
            ThumbnailPickerView(project: project)
        }
        .alert("Delete Project", isPresented: .init(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { projectToDelete = nil }
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    deleteProject(project)
                }
            }
        } message: {
            Text("Are you sure you want to remove \"\(projectToDelete?.displayName ?? "")\" from the catalogue? This does not delete files from disk.")
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
    
    // MARK: - Filter Bar
    
    private let projectTypes = [
        "All", "Web Design", "Video Edit", "Photography", "3D/Motion",
        "Development", "Branding", "Music/Audio", "Documentation", "Other", "Unknown"
    ]
    
    private let nleOptions = [
        "All NLEs", "Premiere Pro", "Final Cut Pro", "DaVinci Resolve",
        "After Effects", "Adobe Audition", "Motion Graphics"
    ]
    
    private let statusOptions: [String] = {
        var opts = ["All Statuses"]
        opts.append(contentsOf: ProjectStatus.allCases.map(\.rawValue))
        return opts
    }()
    
    private let sizeOptions: [(label: String, bytes: Int64)] = [
        ("Any Size", 0),
        ("> 100 MB", 100_000_000),
        ("> 500 MB", 500_000_000),
        ("> 1 GB", 1_000_000_000),
        ("> 5 GB", 5_000_000_000),
        ("> 10 GB", 10_000_000_000),
    ]
    
    private var filterBar: some View {
        let isAnyFilterActive = filterType != "All" || filterNLE != "All NLEs" || filterDateFrom != nil || filterDateTo != nil || filterMinSize > 0 || filterStatus != "All Statuses" || !filterTags.isEmpty
        let activeCount = [
            filterType != "All",
            filterNLE != "All NLEs",
            filterDateFrom != nil,
            filterDateTo != nil,
            filterMinSize > 0,
            filterStatus != "All Statuses",
            !filterTags.isEmpty
        ].filter { $0 }.count
        
        return VStack(spacing: 10) {
            // Top row: main filters
            HStack(spacing: 10) {
                // Type chip
                filterMenu(
                    icon: "doc.text",
                    label: filterType == "All" ? "Type" : filterType,
                    isActive: filterType != "All",
                    color: .blue,
                    options: projectTypes,
                    current: filterType
                ) { filterType = $0 }
                
                // NLE chip
                filterMenu(
                    icon: "film",
                    label: filterNLE == "All NLEs" ? "NLE" : filterNLE,
                    isActive: filterNLE != "All NLEs",
                    color: .purple,
                    options: nleOptions,
                    current: filterNLE
                ) { filterNLE = $0 }
                
                // Status chip
                filterMenu(
                    icon: "circle.lefthalf.filled",
                    label: filterStatus == "All Statuses" ? "Status" : filterStatus,
                    isActive: filterStatus != "All Statuses",
                    color: .orange,
                    options: statusOptions,
                    current: filterStatus
                ) { filterStatus = $0 }
                
                // Size chip
                sizeFilterMenu()
                
                // Separator
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 2)
                
                // Date From
                dateChip(
                    icon: "calendar",
                    label: "From",
                    date: filterDateFrom,
                    color: .cyan
                ) { newDate in
                    filterDateFrom = newDate
                } onClear: {
                    filterDateFrom = nil
                }
                
                // Date To
                dateChip(
                    icon: "calendar.badge.clock",
                    label: "To",
                    date: filterDateTo,
                    color: .teal
                ) { newDate in
                    filterDateTo = newDate
                } onClear: {
                    filterDateTo = nil
                }
                
                Spacer()
                
                // Active filter count + clear
                if isAnyFilterActive {
                    HStack(spacing: 6) {
                        Text("\(activeCount)")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 16, height: 16)
                            .background(Color.accentColor, in: Circle())
                            .foregroundStyle(.white)
                        
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                filterType = "All"
                                filterNLE = "All NLEs"
                                filterDateFrom = nil
                                filterDateTo = nil
                                filterMinSize = 0
                                filterStatus = "All Statuses"
                                filterTags = []
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Clear All")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(.quaternary, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.accentColor.opacity(isAnyFilterActive ? 0.04 : 0), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 0.5)
                }
        }
        .animation(.easeInOut(duration: 0.2), value: isAnyFilterActive)
    }
    
    // MARK: - Filter Chip Components
    
    private func filterMenu(icon: String, label: String, isActive: Bool, color: Color, options: [String], current: String, onSelect: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack {
                        Text(option)
                        if option == current {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterChipLabel(icon: icon, label: label, isActive: isActive, color: color)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
    
    private func sizeFilterMenu() -> some View {
        let isActive = filterMinSize > 0
        let label = filterMinSize == 0 ? "Size" : (sizeOptions.first(where: { $0.bytes == filterMinSize })?.label ?? "Size")
        
        return Menu {
            ForEach(sizeOptions, id: \.bytes) { option in
                Button {
                    filterMinSize = option.bytes
                } label: {
                    HStack {
                        Text(option.label)
                        if option.bytes == filterMinSize {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterChipLabel(icon: "externaldrive", label: label, isActive: isActive, color: .green)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
    
    private func filterChipLabel(icon: String, label: String, isActive: Bool, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? color : .secondary)
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isActive ? color.opacity(0.12) : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? color.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
    
    private func dateChip(icon: String, label: String, date: Date?, color: Color, onSet: @escaping (Date) -> Void, onClear: @escaping () -> Void) -> some View {
        let isActive = date != nil
        
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? color : .secondary)
            
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
            
            DatePicker("", selection: Binding(
                get: { date ?? Date() },
                set: { onSet($0) }
            ), displayedComponents: .date)
            .labelsHidden()
            .scaleEffect(0.85)
            .frame(width: 90)
            
            if isActive {
                Button {
                    withAnimation(.spring(response: 0.3)) { onClear() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            isActive ? color.opacity(0.12) : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? color.opacity(0.3) : .clear, lineWidth: 1)
        )
        .animation(.spring(response: 0.3), value: isActive)
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
            
            // NLE badges (compact)
            if !project.detectedNLEs.isEmpty {
                HStack(spacing: 3) {
                    ForEach(project.nleIcons.prefix(2), id: \.name) { nle in
                        Text(nle.abbreviation)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.purple)
                    }
                }
            }
            
            // Delivered badge
            if project.isDelivered {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .help("Delivered")
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
        case .image, .videoFrame:
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
        Button("Edit Project") { selectedProject = project }
        Button("Change Thumbnail") { showThumbnailPicker = project }
        Button("Project Details") { selectedProject = project }
        Divider()
        if let path = project.drive?.isConnected == true ? project.folderPath : nil {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            }
        }
        Divider()
        Button("Delete Project", role: .destructive) {
            projectToDelete = project
        }
        Divider()
        Button(project.isFavorite ? "Unpin" : "Pin to Top") {
            project.isFavorite.toggle()
            try? modelContext.save()
        }
    }
    
    // MARK: - Actions
    
    @Environment(\.modelContext) private var modelContext
    @Environment(UndoManagerService.self) private var undoService
    
    private func deleteProject(_ project: Project) {
        let snapshot = UndoManagerService.DeletedProjectSnapshot(
            project: project,
            driveId: project.drive?.id,
            clientId: project.client?.id,
            duplicateGroupId: project.duplicateGroup?.id
        )
        undoService.registerProjectDeletion(snapshot: snapshot, context: modelContext)
        modelContext.delete(project)
        try? modelContext.save()
        projectToDelete = nil
    }
    
    // MARK: - Dashboard
    
    private var dashboardHeader: some View {
        HStack(spacing: 12) {
            dashPill(
                value: "\(projects.count)",
                label: "Projects",
                icon: "folder.fill",
                color: .blue
            )
            dashPill(
                value: "\(projects.filter { $0.projectStatus == .inProgress }.count)",
                label: "In Progress",
                icon: "circle.lefthalf.filled",
                color: .orange
            )
            dashPill(
                value: "\(Set(projects.compactMap(\.drive?.id)).count)",
                label: "Drives",
                icon: "externaldrive.fill",
                color: .green
            )
            let recentCount = projects.filter {
                ($0.projectDate ?? .distantPast) > Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            }.count
            dashPill(
                value: "\(recentCount)",
                label: "This Week",
                icon: "clock.fill",
                color: .purple
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
    
    private func dashPill(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    
    private var groupedGridView: some View {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        
        let todayProjects = projects.filter { ($0.projectDate ?? .distantPast) >= today }
        let thisWeekProjects = projects.filter {
            let d = $0.projectDate ?? .distantPast
            return d >= weekAgo && d < today
        }
        let thisMonthProjects = projects.filter {
            let d = $0.projectDate ?? .distantPast
            return d >= monthAgo && d < weekAgo
        }
        let earlierProjects = projects.filter { ($0.projectDate ?? .distantPast) < monthAgo }
        
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(
                [(title: "Today", items: todayProjects),
                 (title: "This Week", items: thisWeekProjects),
                 (title: "This Month", items: thisMonthProjects),
                 (title: "Earlier", items: earlierProjects)].filter { !$0.items.isEmpty },
                id: \.title
            ) { group in
                Text(group.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(group.items, id: \.id) { project in
                        ProjectCardView(
                            project: project,
                            onEdit: { selectedProject = project },
                            onChangeThumbnail: { showThumbnailPicker = project },
                            onShowDetail: { selectedProject = project },
                            onOpenExplorer: { explorerProject = project }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: projects.count)
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            let driveSet = Set(sortedProjects.compactMap(\.drive?.id))
            let clientCount = Set(sortedProjects.compactMap(\.client?.id)).count
            let connectedCount = sortedProjects.filter { $0.drive?.isConnected == true }.count
            let totalSize = sortedProjects.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let favCount = sortedProjects.filter(\.isFavorite).count
            
            HStack(spacing: 14) {
                statusItem("\(sortedProjects.count)", label: "projects", icon: "folder.fill", color: .blue)
                statusItem("\(clientCount)", label: "clients", icon: "person.2.fill", color: .purple)
                statusItem("\(driveSet.count)", label: "drives", icon: "externaldrive.fill", color: .green)
                statusItem(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file), label: "total", icon: "internaldisk", color: .orange)
                
                if connectedCount < sortedProjects.count {
                    statusItem("\(sortedProjects.count - connectedCount)", label: "offline", icon: "eject.fill", color: .gray)
                }
                if favCount > 0 {
                    statusItem("\(favCount)", label: "pinned", icon: "pin.fill", color: .yellow)
                }
            }
            
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
    
    private func statusItem(_ value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(color.opacity(0.7))
            Text("\(value) \(label)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - File Search Results
    
    struct FileMatch: Identifiable {
        var id: UUID { file.id }
        let file: MediaFile
        let project: Project
        let matchField: String    // e.g. "Visual Tags", "Codec", "Camera"
        let matchValue: String    // e.g. "market scene", "ProRes 422 HQ"
    }
    
    /// Files matching the current search across all projects, with match context
    private var matchingFiles: [FileMatch] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        var matches: [FileMatch] = []
        
        for project in allProjects {
            for file in project.mediaFiles {
                var matchField = ""
                var matchValue = ""
                
                if file.filename.lowercased().contains(query) {
                    matchField = "Filename"
                    matchValue = file.filename
                } else if let codec = file.codec, codec.lowercased().contains(query) {
                    matchField = "Codec"
                    matchValue = codec
                } else if let camera = file.cameraModel, camera.lowercased().contains(query) {
                    matchField = "Camera"
                    matchValue = camera
                } else if let cs = file.colorSpace, cs.lowercased().contains(query) {
                    matchField = "Color Space"
                    matchValue = cs
                } else if let res = file.resolution, res.lowercased().contains(query) {
                    matchField = "Resolution"
                    matchValue = res
                } else if file.metadataBadge.lowercased().contains(query) {
                    matchField = "Specs"
                    matchValue = file.metadataBadge
                } else if let tag = file.visualTags.first(where: { $0.lowercased().contains(query) }) {
                    matchField = "Visual Tags"
                    matchValue = file.visualTags.prefix(5).joined(separator: ", ")
                } else if file.visualDescription.lowercased().contains(query) {
                    matchField = "AI Description"
                    let desc = file.visualDescription
                    if let range = desc.lowercased().range(of: query) {
                        let startIdx = desc.index(range.lowerBound, offsetBy: -30, limitedBy: desc.startIndex) ?? desc.startIndex
                        let endIdx = desc.index(range.upperBound, offsetBy: 30, limitedBy: desc.endIndex) ?? desc.endIndex
                        var snippet = String(desc[startIdx..<endIdx])
                        if startIdx != desc.startIndex { snippet = "…" + snippet }
                        if endIdx != desc.endIndex { snippet = snippet + "…" }
                        matchValue = snippet
                    } else {
                        matchValue = String(desc.prefix(60))
                    }
                } else if file.relativePath.lowercased().contains(query) {
                    matchField = "Path"
                    matchValue = file.relativePath
                } else if file.fileExtension.lowercased().contains(query) {
                    matchField = "Extension"
                    matchValue = "." + file.fileExtension
                } else {
                    continue
                }
                
                matches.append(FileMatch(file: file, project: project, matchField: matchField, matchValue: matchValue))
                if matches.count >= 50 { return matches }
            }
        }
        return matches
    }
    
    /// Build text with the query highlighted in cyan
    private func highlightedText(_ text: String, query: String) -> Text {
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()
        
        guard let range = lowerText.range(of: lowerQuery) else {
            return Text(text).foregroundColor(.secondary)
        }
        
        let before = String(text[text.startIndex..<range.lowerBound])
        let matched = String(text[range.lowerBound..<range.upperBound])
        let after = String(text[range.upperBound..<text.endIndex])
        
        return Text(before).foregroundColor(.secondary) +
            Text(matched).foregroundColor(.cyan).bold() +
            Text(after).foregroundColor(.secondary)
    }
    
    @ViewBuilder
    private func fileResultRow(_ match: FileMatch) -> some View {
        let file = match.file
        let project = match.project
        
        HStack(spacing: 10) {
            // Thumbnail
            SearchFileThumbnail(absolutePath: project.folderPath + "/" + file.relativePath, isVideo: file.fileType == .video, isImage: file.fileType == .image)
                .frame(width: 44, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(file.filename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                // Match context — WHY this file matched
                HStack(spacing: 4) {
                    Text(match.matchField)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan.opacity(0.8))
                    
                    highlightedText(match.matchValue, query: searchText)
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)
                        Text(project.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    
                    if file.relativePath != file.filename {
                        Text(file.relativePath)
                            .font(.system(size: 8))
                            .foregroundStyle(.gray.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            
            Spacer()
            
            if !file.metadataBadge.isEmpty {
                Text(file.metadataBadge)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.cyan.opacity(0.1), in: Capsule())
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            }
            
            if let drive = project.drive {
                HStack(spacing: 2) {
                    Circle()
                        .fill(drive.isConnected ? Color.green : Color.gray)
                        .frame(width: 5, height: 5)
                    Text(drive.name)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(file.formattedSize)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.02))
        .contentShape(Rectangle())
        .onTapGesture {
            // Open file explorer navigated to this file
            explorerInitialFile = file.relativePath
            explorerProject = project
        }
    }
    
    private func fileTypeColor(_ type: MediaFileType) -> Color {
        switch type {
        case .video: return .blue
        case .audio: return .green
        case .image: return .purple
        case .projectFile: return .orange
        case .other: return .gray
        }
    }
}

// MARK: - Search File Thumbnail

import AVFoundation

/// Lightweight thumbnail for search result rows — loads async with rate limiting
struct SearchFileThumbnail: View {
    let absolutePath: String
    let isVideo: Bool
    let isImage: Bool
    
    @State private var thumbnail: NSImage?
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        Group {
            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Placeholder with icon
                ZStack {
                    Color(white: 0.12)
                    Image(systemName: isVideo ? "film" : isImage ? "photo" : "doc")
                        .font(.system(size: 11))
                        .foregroundStyle(isVideo ? .blue : isImage ? .purple : .gray)
                }
            }
        }
        .onAppear {
            guard thumbnail == nil, FileManager.default.fileExists(atPath: absolutePath) else { return }
            loadTask = Task {
                await ThumbnailQueue.shared.enqueue {
                    await loadThumbnail()
                }
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }
    
    private func loadThumbnail() async {
        let fileURL = URL(fileURLWithPath: absolutePath)
        
        if isVideo {
            let asset = AVAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 80, height: 80)
            
            let time = CMTime(seconds: 1, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                guard !Task.isCancelled else { return }
                let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run { thumbnail = img }
            }
        } else if isImage {
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 80,
                kCGImageSourceShouldCacheImmediately: false
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
            guard !Task.isCancelled else { return }
            let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            await MainActor.run { thumbnail = img }
        }
    }
}
