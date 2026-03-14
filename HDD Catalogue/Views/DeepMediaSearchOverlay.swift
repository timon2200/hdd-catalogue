import SwiftUI
import SwiftData

/// Deep Media Search overlay — ⌘⇧D
/// Unified search across ALL indexed files on ALL drives (even disconnected).
struct DeepMediaSearchOverlay: View {
    @Binding var isPresented: Bool
    let deepMediaService: DeepMediaSearchService
    
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]
    
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var searchMode: SearchMode = .files
    @State private var results: [FileSearchResult] = []
    @State private var activeSpecFilters: Set<SpecChip> = []
    @FocusState private var isSearchFocused: Bool
    
    @State private var debounceTask: Task<Void, Never>?
    @State private var showFileExplorer = false
    @State private var explorerResult: FileSearchResult?
    
    enum SearchMode: String, CaseIterable {
        case files = "Files"
        case specs = "Specs"
        case visual = "Visual"
        
        var icon: String {
            switch self {
            case .files: return "doc.text.magnifyingglass"
            case .specs: return "slider.horizontal.3"
            case .visual: return "eye.fill"
            }
        }
        
        var placeholder: String {
            switch self {
            case .files: return "Search by filename, path, codec…"
            case .specs: return "Filter by resolution, codec, fps…"
            case .visual: return "sunset, interview, aerial, nature…"
            }
        }
    }
    
    enum SpecChip: String, CaseIterable {
        case res4K = "4K"
        case res8K = "8K"
        case fps120 = "120fps"
        case fps60 = "60fps"
        case prores = "ProRes"
        case h265 = "H.265"
        case h264 = "H.264"
        case typeVideo = "Video"
        case typeImage = "Image"
        case typeAudio = "Audio"
        
        var filter: FileSearchFilter {
            switch self {
            case .res4K:    return FileSearchFilter(minResolutionWidth: 3840)
            case .res8K:    return FileSearchFilter(minResolutionWidth: 7680)
            case .fps120:   return FileSearchFilter(minFrameRate: 119.0)
            case .fps60:    return FileSearchFilter(minFrameRate: 59.0)
            case .prores:   return FileSearchFilter(codec: "ProRes")
            case .h265:     return FileSearchFilter(codec: "H.265")
            case .h264:     return FileSearchFilter(codec: "H.264")
            case .typeVideo: return FileSearchFilter(fileType: .video)
            case .typeImage: return FileSearchFilter(fileType: .image)
            case .typeAudio: return FileSearchFilter(fileType: .audio)
            }
        }
        
        var color: Color {
            switch self {
            case .res4K, .res8K: return .blue
            case .fps120, .fps60: return .orange
            case .prores, .h265, .h264: return .purple
            case .typeVideo: return .blue
            case .typeImage: return .purple
            case .typeAudio: return .green
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { close() }
            
            // Search panel
            VStack(spacing: 0) {
                // Header with search + mode picker
                searchHeader
                
                Divider()
                
                // Spec filter chips (always visible in specs mode)
                if searchMode == .specs {
                    specChipsBar
                    Divider()
                }
                
                // Content
                if results.isEmpty && query.isEmpty && activeSpecFilters.isEmpty {
                    emptyStateView
                } else if results.isEmpty {
                    noResultsView
                } else {
                    resultsListView
                }
                
                // Footer
                if !results.isEmpty {
                    Divider()
                    HStack {
                        Text("\(results.count) file\(results.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        let indexedCount = projects.filter(\.isDeepIndexed).count
                        Text("\(indexedCount) projects indexed")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        
                        shortcutHint("↩", "Open")
                        shortcutHint("esc", "Close")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .frame(width: 700)
            .frame(maxHeight: 560)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan.opacity(0.3), .blue.opacity(0.2), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .cyan.opacity(0.15), radius: 40, y: 10)
        }
        .sheet(isPresented: $showFileExplorer) {
            if let result = explorerResult {
                MediaFileExplorerView(
                    project: result.project,
                    initialFile: result.file,
                    isPresented: $showFileExplorer
                )
            }
        }
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < results.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onKeyPress(.return) {
            openSelected()
            return .handled
        }
    }
    
    // MARK: - Header
    
    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: searchMode.icon)
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            TextField(searchMode.placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .onSubmit { performSearch() }
                .onChange(of: query) { _, newValue in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled else { return }
                        performSearch()
                    }
                }
            
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Mode picker
            Picker("", selection: $searchMode) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .onChange(of: searchMode) { _, _ in
                results = []
                activeSpecFilters = []
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Spec Chips
    
    private var specChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpecChip.allCases, id: \.self) { chip in
                    Button {
                        if activeSpecFilters.contains(chip) {
                            activeSpecFilters.remove(chip)
                        } else {
                            activeSpecFilters.insert(chip)
                        }
                        performSearch()
                    } label: {
                        Text(chip.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                activeSpecFilters.contains(chip)
                                ? chip.color.opacity(0.2)
                                : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        activeSpecFilters.contains(chip) ? chip.color : Color.gray.opacity(0.3),
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(
                                activeSpecFilters.contains(chip) ? chip.color : .secondary
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                if !activeSpecFilters.isEmpty {
                    Button {
                        activeSpecFilters = []
                        performSearch()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("Clear")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
    
    // MARK: - State Views
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Deep Media Search")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text("Search across every file on every drive — codecs, cameras, specs, and more")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            
            HStack(spacing: 16) {
                exampleChip("ProRes")
                exampleChip("4K")
                exampleChip("ZV-E1")
                exampleChip(".mogrt")
            }
            .padding(.top, 4)
            
            let indexedCount = projects.filter(\.isDeepIndexed).count
            if indexedCount > 0 {
                Text("\(indexedCount) of \(projects.count) projects deep-indexed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 4) {
                    Text("No projects deep-indexed yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Use the \"Deep Index\" button in the toolbar to start")
                        .font(.caption2)
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No files found")
                .foregroundStyle(.secondary)
            
            let indexedCount = projects.filter(\.isDeepIndexed).count
            if indexedCount == 0 {
                Text("Deep-index your projects first to search files")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
    
    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        fileResultRow(result, isSelected: index == selectedIndex)
                            .id(index)
                            .onTapGesture {
                                selectedIndex = index
                                openSelected()
                            }
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedIndex) { _, newValue in
                proxy.scrollTo(newValue, anchor: .center)
            }
        }
    }
    
    // MARK: - Result Row
    
    @ViewBuilder
    private func fileResultRow(_ result: FileSearchResult, isSelected: Bool) -> some View {
        let file = result.file
        
        HStack(spacing: 10) {
            // File type icon
            Image(systemName: file.typeIcon)
                .font(.system(size: 14))
                .foregroundStyle(fileTypeColor(file.fileType))
                .frame(width: 24, height: 24)
                .background(fileTypeColor(file.fileType).opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Parent project
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(result.project.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Relative path (truncated)
                    if file.relativePath != file.filename {
                        Text(file.relativePath)
                            .font(.caption2)
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            
            Spacer()
            
            // Metadata badge
            if !file.metadataBadge.isEmpty {
                Text(file.metadataBadge)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.cyan.opacity(0.1), in: Capsule())
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            }
            
            // Drive
            if let drive = result.drive {
                HStack(spacing: 3) {
                    Image(systemName: drive.isConnected ? "externaldrive.fill" : "externaldrive")
                        .font(.system(size: 9))
                        .foregroundStyle(drive.isConnected ? .green : .gray)
                    Text(drive.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Size
            Text(file.formattedSize)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isSelected
            ? Color.cyan.opacity(0.12)
            : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                explorerResult = result
                showFileExplorer = true
            } label: {
                Label("Open in File Explorer", systemImage: "rectangle.expand.vertical")
            }
            if result.drive?.isConnected == true {
                Button {
                    let filePath = result.project.folderPath + "/" + result.file.relativePath
                    NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: result.project.folderPath)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func fileTypeColor(_ type: MediaFileType) -> Color {
        switch type {
        case .video: return .blue
        case .audio: return .green
        case .image: return .purple
        case .projectFile: return .orange
        case .other: return .gray
        }
    }
    
    private func exampleChip(_ text: String) -> some View {
        Button {
            query = text
            performSearch()
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.cyan.opacity(0.1), in: Capsule())
                .foregroundStyle(.cyan)
        }
        .buttonStyle(.plain)
    }
    
    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        // Build combined filter from active spec chips
        var filter = FileSearchFilter()
        for chip in activeSpecFilters {
            let cf = chip.filter
            // Merge: take the highest resolution, fps, etc.
            if let w = cf.minResolutionWidth {
                filter.minResolutionWidth = max(filter.minResolutionWidth ?? 0, w)
            }
            if let c = cf.codec {
                filter.codec = c
            }
            if let fps = cf.minFrameRate {
                filter.minFrameRate = max(filter.minFrameRate ?? 0, fps)
            }
            if let t = cf.fileType {
                filter.fileType = t
            }
        }
        
        results = deepMediaService.searchFiles(
            query: query,
            allProjects: Array(projects),
            filters: filter
        )
        selectedIndex = 0
    }
    
    private func openSelected() {
        guard selectedIndex < results.count else { return }
        let result = results[selectedIndex]
        
        // If drive is connected, try to reveal file in Finder
        if result.drive?.isConnected == true {
            let filePath = result.project.folderPath + "/" + result.file.relativePath
            NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: result.project.folderPath)
        } else {
            // Otherwise, open the project detail
            NotificationCenter.default.post(
                name: .openProjectDetail,
                object: result.project.id
            )
        }
        close()
    }
    
    private func close() {
        withAnimation(.easeOut(duration: 0.15)) {
            isPresented = false
        }
    }
}
