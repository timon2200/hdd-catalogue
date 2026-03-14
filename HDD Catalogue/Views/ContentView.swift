import SwiftUI
import SwiftData

/// Main content view with NavigationSplitView — sidebar + detail grid.
/// Enhanced with Phase 1: NLE filtering, video thumbnail generation, camera/NLE search.
struct ContentView: View {
    let driveMonitor: DriveMonitor
    let scanEngine: ScanEngine
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Drive.name) private var drives: [Drive]
    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var projects: [Project]
    @Query private var duplicateGroups: [DuplicateGroup]
    
    @State private var selectedDrive: Drive?
    @State private var selectedClient: Client?
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var isAIProcessing = false
    @State private var aiError: String?
    @State private var showDuplicates = false
    @State private var openedProjectFromSearch: Project?
    
    // Advanced filters
    @State private var showFilters = false
    @State private var filterType: String = "All"
    @State private var filterDateFrom: Date?
    @State private var filterDateTo: Date?
    @State private var filterMinSize: Int64 = 0
    @State private var filterNLE: String = "All NLEs"
    @State private var filterStatus: String = "All Statuses"
    @State private var filterTags: Set<String> = []
    @State private var showQuickSearch = false
    @State private var selectedSmartBin: SmartBin?
    @State private var showStorageDashboard = false
    
    // Visual Search & Drawer
    @State private var findSimilarProject: Project?
    @State private var drawerProject: Project?
    
    // File Explorer
    @State private var explorerProject: Project?
    @State private var explorerInitialFile: String?  // Relative file path for search navigation
    
    @AppStorage("autoScanOnMount") private var autoScanOnMount = true
    @AppStorage("scanDepth") private var scanDepth = 1
    @AppStorage("enableVisualIndexing") private var enableVisualIndexing = true
    @AppStorage("deepScanMode") private var deepScanMode = "frames"
    
    @State private var geminiService = GeminiService()
    @State private var visualSearchService = VisualSearchService()
    @State private var deepMediaService = DeepMediaSearchService()
    
    var filteredProjects: [Project] {
        var result = projects
        
        // Filter by drive
        if let drive = selectedDrive {
            result = result.filter { $0.drive?.id == drive.id }
        }
        
        // Filter by client
        if let client = selectedClient {
            result = result.filter { $0.client?.id == client.id }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { project in
                // Project-level search
                project.displayName.lowercased().contains(query) ||
                project.folderName.lowercased().contains(query) ||
                project.projectType.lowercased().contains(query) ||
                project.aiSummary.lowercased().contains(query) ||
                (project.client?.name.lowercased().contains(query) ?? false) ||
                (project.drive?.name.lowercased().contains(query) ?? false) ||
                project.detectedNLEs.contains(where: { $0.lowercased().contains(query) }) ||
                project.cameraSources.contains(where: { $0.lowercased().contains(query) }) ||
                project.tags.contains(where: { $0.lowercased().contains(query) }) ||
                project.notes.lowercased().contains(query) ||
                project.visualTags.contains(where: { $0.lowercased().contains(query) }) ||
                projectHasMatchingFile(project, query: query)
            }
        }
        
        // Advanced filter: project type
        if filterType != "All" {
            result = result.filter { $0.projectType == filterType }
        }
        
        // Advanced filter: NLE
        if filterNLE != "All NLEs" {
            result = result.filter { $0.detectedNLEs.contains(filterNLE) }
        }
        
        // Advanced filter: date range
        if let from = filterDateFrom {
            result = result.filter { ($0.projectDate ?? .distantPast) >= from }
        }
        if let to = filterDateTo {
            result = result.filter { ($0.projectDate ?? .distantFuture) <= to }
        }
        
        // Advanced filter: minimum size
        if filterMinSize > 0 {
            result = result.filter { $0.sizeBytes >= filterMinSize }
        }
        
        // Phase 2: status filter
        if filterStatus != "All Statuses" {
            result = result.filter { $0.statusRaw == filterStatus }
        }
        
        // Phase 2: tag filter
        if !filterTags.isEmpty {
            result = result.filter { project in
                filterTags.isSubset(of: Set(project.tags))
            }
        }
        
        return result.sorted { ($0.projectDate ?? .distantPast) > ($1.projectDate ?? .distantPast) }
    }
    
    var activeDuplicates: [DuplicateGroup] {
        duplicateGroups.filter { !$0.isDismissed && $0.projects.count > 1 }
    }
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                drives: drives,
                clients: clients,
                projects: projects,
                selectedDrive: $selectedDrive,
                selectedClient: $selectedClient,
                filterStatus: $filterStatus,
                filterTags: $filterTags,
                scanEngine: scanEngine,
                duplicateCount: activeDuplicates.count,
                showDuplicates: $showDuplicates,
                onScanDrive: { drive in
                    showStorageDashboard = false
                    Task { await scanAndCategorize(drive: drive) }
                },
                onScanAll: {
                    showStorageDashboard = false
                    Task { await scanAllDrives() }
                },
                showStorageDashboard: $showStorageDashboard,
                onSelectSmartBin: { bin in
                    selectedSmartBin = bin
                    selectedDrive = nil
                    selectedClient = nil
                    showStorageDashboard = false
                }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            .onChange(of: selectedDrive) { _, _ in showStorageDashboard = false }
            .onChange(of: selectedClient) { _, _ in showStorageDashboard = false }
        } detail: {
            if showStorageDashboard {
                StorageDashboardView(
                    drives: Array(drives),
                    projects: Array(projects),
                    clients: Array(clients)
                )
                .transition(.opacity)
            } else if let explorerProj = explorerProject {
                ProjectFileExplorerView(
                    project: explorerProj,
                    isPresented: $explorerProject,
                    initialFilePath: explorerInitialFile,
                    searchText: $searchText,
                    deepMediaService: deepMediaService
                )
                .transition(.opacity)
                .onAppear { explorerInitialFile = nil }
            } else {
            HStack(spacing: 0) {
                ZStack {
                    CatalogueGridView(
                        projects: selectedSmartBin != nil
                            ? selectedSmartBin!.matchingProjects(from: Array(projects)).sorted { ($0.projectDate ?? .distantPast) > ($1.projectDate ?? .distantPast) }
                            : filteredProjects,
                        allProjects: Array(projects),
                        clients: clients,
                        searchText: $searchText,
                        selectedClient: $selectedClient,
                        isAIProcessing: isAIProcessing,
                        showFilters: $showFilters,
                        filterType: $filterType,
                        filterDateFrom: $filterDateFrom,
                        filterDateTo: $filterDateTo,
                        filterMinSize: $filterMinSize,
                        filterNLE: $filterNLE,
                        filterStatus: $filterStatus,
                        filterTags: $filterTags,
                        showDashboard: selectedSmartBin == nil && selectedDrive == nil && selectedClient == nil && filterStatus == "All Statuses" && filterTags.isEmpty && searchText.isEmpty,
                        selectedProject: $drawerProject,
                        explorerProject: $explorerProject,
                        explorerInitialFile: $explorerInitialFile
                    )
                
                // Scan progress overlay
                if scanEngine.isScanning {
                    ScanProgressView(scanEngine: scanEngine)
                }
                
                // AI thinking panel
                if isAIProcessing {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            AIThinkingPanel(geminiService: geminiService)
                                .frame(maxHeight: 320)
                                .frame(width: 380)
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                
                // Visual indexing progress (bottom-left)
                if visualSearchService.isVisualIndexing {
                    VStack {
                        Spacer()
                        HStack {
                            visualIndexingPanel
                                .frame(width: 320)
                            Spacer()
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .padding(16)
                }
                
                // Duplicate resolution sheet
                if showDuplicates {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showDuplicates = false }
                    
                    DuplicateResolutionView(
                        duplicateGroups: activeDuplicates,
                        onDismiss: { showDuplicates = false }
                    )
                    .frame(maxWidth: 700, maxHeight: 500)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Quick Search overlay (⌘K)
                if showQuickSearch {
                    QuickSearchOverlay(isPresented: $showQuickSearch)
                        .transition(.opacity)
                }
                

                
                // Find Similar overlay
                if let project = findSimilarProject {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture { findSimilarProject = nil }
                        
                        FindSimilarSheet(
                            sourceProject: project,
                            visualSearchService: visualSearchService,
                            isPresented: $findSimilarProject
                        )
                    }
                    .transition(.opacity)
                }
                

                
                // Deep media indexing progress (bottom-right)
                if deepMediaService.isIndexing {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            deepIndexingPanel
                                .frame(width: 320)
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .padding(16)
                }
            }
            .animation(.spring(response: 0.4), value: showDuplicates)
            .animation(.spring(response: 0.4), value: isAIProcessing)
            .animation(.spring(response: 0.3), value: visualSearchService.isVisualIndexing)
            .animation(.easeOut(duration: 0.15), value: showQuickSearch)
            .animation(.easeOut(duration: 0.2), value: findSimilarProject?.id)
            .animation(.spring(response: 0.3), value: deepMediaService.isIndexing)
                
                // Right drawer
                if let project = drawerProject {
                    ProjectDrawerView(
                        project: project,
                        isPresented: $drawerProject
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: drawerProject?.id)
            }
        }
        .animation(.easeOut(duration: 0.25), value: explorerProject?.id)
        .searchable(text: $searchText, prompt: "Search projects, clients, cameras, codecs, files…")
        .onReceive(NotificationCenter.default.publisher(for: .openProjectDetail)) { notification in
            if let projectId = notification.object as? UUID,
               let project = projects.first(where: { $0.id == projectId }) {
                drawerProject = project
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleQuickSearch)) { _ in
            showQuickSearch.toggle()
        }

        .onReceive(NotificationCenter.default.publisher(for: .findSimilarProject)) { notification in
            if let projectId = notification.object as? UUID,
               let project = projects.first(where: { $0.id == projectId }) {
                findSimilarProject = project
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if isAIProcessing {
                    ProgressView()
                        .controlSize(.small)
                    Text(geminiService.currentStep.isEmpty ? "AI analyzing…" : geminiService.currentStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                

                
                // Deep Index button
                Menu {
                    Button {
                        Task {
                            deepScanMode = "frames"
                            await runDeepIndexing()
                        }
                    } label: {
                        Label("Frames Only (Fast)", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        Task {
                            deepScanMode = "motion"
                            await runDeepIndexing()
                        }
                    } label: {
                        Label("Enhanced Motion (Video)", systemImage: "video.fill")
                    }
                } label: {
                    Label("Deep Index", systemImage: deepMediaService.isIndexing ? "arrow.triangle.2.circlepath" : "square.stack.3d.up")
                }
                .disabled(deepMediaService.isIndexing || projects.filter({ $0.drive?.isConnected == true }).isEmpty)
                .help("Index all files for deep media search")
                
                Menu {
                    Button("Categorize Uncategorized") {
                        Task { await runAICategorization(forceAll: false) }
                    }
                    Button("Re-analyze All Projects") {
                        Task { await runAICategorization(forceAll: true) }
                    }
                } label: {
                    Label("AI Categorize", systemImage: "sparkles")
                }
                .disabled(isAIProcessing || projects.isEmpty)
                .help("Run AI categorization on projects")
                
                if !activeDuplicates.isEmpty {
                    Button {
                        showDuplicates.toggle()
                    } label: {
                        Label("Duplicates (\(activeDuplicates.count))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                
                Button {
                    showFilters.toggle()
                } label: {
                    Label("Filters", systemImage: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help("Toggle advanced filters")
                
                Menu {
                    Button("Export as CSV…") {
                        ExportService.exportCSV(projects: filteredProjects)
                    }
                    Button("Export as JSON…") {
                        ExportService.exportJSON(projects: filteredProjects)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(filteredProjects.isEmpty)
            }
        }
        .alert("AI Error", isPresented: .init(get: { aiError != nil }, set: { if !$0 { aiError = nil } })) {
            Button("OK") { aiError = nil }
            Button("Open Settings") {
                aiError = nil
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        } message: {
            Text(aiError ?? "")
        }
        .onAppear {
            setupDriveMonitoring()
        }
    }
    
    // MARK: - Drive Monitoring & Scanning
    
    private func setupDriveMonitoring() {
        Task { @MainActor in
            driveMonitor.startMonitoring(
                modelContext: modelContext,
                scanEngine: scanEngine
            ) { drive in
                if autoScanOnMount {
                    Task { await scanAndCategorize(drive: drive) }
                }
            }
        }
    }
    
    private func scanAllDrives() async {
        let connectedDrives = drives.filter(\.isConnected)
        for drive in connectedDrives {
            await scanAndCategorize(drive: drive)
        }
    }
    
    private func scanAndCategorize(drive: Drive) async {
        // Step 1: Scan folders (now includes Phase 1 deep analysis)
        let scannedProjects = await scanEngine.scanDrive(drive, modelContext: modelContext, maxDepth: scanDepth)
        
        // Insert new projects
        for project in scannedProjects where project.drive == nil {
            project.drive = drive
            modelContext.insert(project)
        }
        try? modelContext.save()
        
        // Step 2: Generate video thumbnails for projects without custom thumbnails
        await generateVideoThumbnails(for: scannedProjects)
        
        // Step 3: Visual indexing (if enabled)
        if enableVisualIndexing {
            await indexProjectVisuals(for: scannedProjects)
        }
        
        // Notify scan completion
        NotificationService.notifyScanComplete(driveName: drive.name, projectCount: scannedProjects.count)
        
        // Step 4: AI categorization
        await runAICategorization(forceAll: false)
    }
    
    /// Generates video frame thumbnails for projects that have video files
    /// but no user-set thumbnail.
    private func generateVideoThumbnails(for projects: [Project]) async {
        for project in projects {
            // Only generate if thumbnail is still auto/default and drive is connected
            guard project.thumbnailType == .auto,
                  project.drive?.isConnected == true else { continue }
            
            // Only try for projects that have video files
            guard let summary = project.mediaSummary, summary.videoCount > 0 else { continue }
            
            let projectURL = URL(fileURLWithPath: project.folderPath)
            if let thumbnailData = await VideoThumbnailService.generateThumbnail(for: projectURL) {
                project.thumbnailData = thumbnailData
                project.thumbnailType = .videoFrame
            }
        }
        try? modelContext.save()
    }
    
    /// Indexes project thumbnails using Apple Vision for visual search.
    private func indexProjectVisuals(for projects: [Project]) async {
        let toIndex = projects.filter { !$0.isVisuallyIndexed && $0.thumbnailData != nil }
        guard !toIndex.isEmpty else { return }
        
        await MainActor.run {
            visualSearchService.isVisualIndexing = true
            visualSearchService.visualIndexingTotal = toIndex.count
            visualSearchService.visualIndexingCompleted = 0
            visualSearchService.visualIndexingTagsFound = 0
            visualSearchService.visualIndexingProgress = 0
        }
        
        for (index, project) in toIndex.enumerated() {
            await MainActor.run {
                visualSearchService.visualIndexingCurrentProject = project.displayName
                visualSearchService.visualIndexingProgress = Double(index) / Double(toIndex.count)
            }
            
            guard let thumbnailData = project.thumbnailData else { continue }
            
            do {
                let result = try await visualSearchService.indexProjectVisuals(thumbnailData: thumbnailData)
                project.visualTags = result.tags
                project.visualDescription = result.description
                await MainActor.run {
                    visualSearchService.visualIndexingCompleted += 1
                    visualSearchService.visualIndexingTagsFound += result.tags.count
                }
            } catch {
                print("⚠️ Visual indexing failed for \(project.displayName): \(error.localizedDescription)")
                await MainActor.run {
                    visualSearchService.visualIndexingCompleted += 1
                }
            }
        }
        
        await MainActor.run {
            visualSearchService.visualIndexingProgress = 1.0
            visualSearchService.isVisualIndexing = false
        }
        try? modelContext.save()
    }
    
    // MARK: - Visual Indexing Progress Panel
    
    private var visualIndexingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                // Mini progress ring
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 3)
                        .frame(width: 32, height: 32)
                    Circle()
                        .trim(from: 0, to: visualSearchService.visualIndexingProgress)
                        .stroke(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: visualSearchService.visualIndexingProgress)
                    
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Visual Indexing")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(visualSearchService.visualIndexingCompleted) / \(visualSearchService.visualIndexingTotal) projects")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
                
                Text("\(Int(visualSearchService.visualIndexingProgress * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
                    .monospacedDigit()
            }
            
            // Current project
            if !visualSearchService.visualIndexingCurrentProject.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple.opacity(0.6))
                    Text(visualSearchService.visualIndexingCurrentProject)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            // Tags found so far
            if visualSearchService.visualIndexingTagsFound > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.purple.opacity(0.5))
                    Text("\(visualSearchService.visualIndexingTagsFound) tags discovered")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .blue.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .purple.opacity(0.1), radius: 12, y: 4)
    }
    
    // MARK: - Deep Indexing Progress Panel
    
    private var deepIndexingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                // Mini progress ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                        .frame(width: 32, height: 32)
                    Circle()
                        .trim(from: 0, to: deepMediaService.indexingProgress)
                        .stroke(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: deepMediaService.indexingProgress)
                    
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 11))
                        .foregroundStyle(.cyan)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deep Indexing")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 4) {
                        Text("\(deepMediaService.indexingFilesProcessed) / \(deepMediaService.indexingFilesTotal) files")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if !deepMediaService.indexingElapsedTime.isEmpty {
                            Text("· \(deepMediaService.indexingElapsedTime)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(deepMediaService.indexingProgress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .monospacedDigit()
                    if !deepMediaService.indexingEstimatedTimeRemaining.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.system(size: 7))
                                .foregroundStyle(.cyan.opacity(0.6))
                            Text("~\(deepMediaService.indexingEstimatedTimeRemaining)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.cyan.opacity(0.7))
                                .monospacedDigit()
                        }
                    }
                }
                
                Button {
                    deepMediaService.stopIndexing()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(.red.opacity(0.25))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Stop indexing")
            }
            
            // Current project
            if !deepMediaService.indexingCurrentProject.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.cyan.opacity(0.6))
                    Text(deepMediaService.indexingCurrentProject)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            // Status line (shows 🏷️ / 🤖 / ✅ during AI processing)
            if !deepMediaService.indexingStatus.isEmpty {
                Text(deepMediaService.indexingStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.15), value: deepMediaService.indexingStatus)
            }
            
            // Ollama AI description counters
            if deepMediaService.ollamaService.descriptionsGenerated > 0 || deepMediaService.ollamaService.descriptionsFailed > 0 {
                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Image(systemName: "brain")
                            .font(.system(size: 8))
                            .foregroundStyle(.cyan)
                        Text("\(deepMediaService.ollamaService.descriptionsGenerated) described")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.cyan)
                            .monospacedDigit()
                    }
                    if deepMediaService.ollamaService.descriptionsFailed > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                            Text("\(deepMediaService.ollamaService.descriptionsFailed) failed")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                                .monospacedDigit()
                        }
                    }
                }
            }
            
            // Latest AI description preview
            if !deepMediaService.ollamaService.currentDescription.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest AI description:")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.cyan.opacity(0.6))
                    Text(deepMediaService.ollamaService.currentDescription)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .italic()
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [.cyan.opacity(0.3), .blue.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .cyan.opacity(0.1), radius: 12, y: 4)
    }
    
    /// Deep-indexes all connected projects for file-level search.
    private func runDeepIndexing() async {
        let connectedProjects = projects.filter { $0.drive?.isConnected == true }
        guard !connectedProjects.isEmpty else { return }
        await deepMediaService.deepIndexProjects(Array(connectedProjects), modelContext: modelContext, useMotionScan: deepScanMode == "motion")
    }
    
    /// Runs AI categorization and duplicate detection.
    /// Check if any deep-indexed media file in a project matches the query
    private func projectHasMatchingFile(_ project: Project, query: String) -> Bool {
        project.mediaFiles.contains { file in
            file.filename.lowercased().contains(query) ||
            (file.codec ?? "").lowercased().contains(query) ||
            file.relativePath.lowercased().contains(query) ||
            file.metadataBadge.lowercased().contains(query) ||
            file.visualTags.contains(where: { $0.lowercased().contains(query) })
        }
    }
    
    private func runAICategorization(forceAll: Bool) async {
        let targetProjects: [Project]
        if forceAll {
            targetProjects = projects.filter { !$0.isEdited }
        } else {
            targetProjects = projects.filter { !$0.isEdited && $0.projectType == "Unknown" }
        }
        
        guard !targetProjects.isEmpty else {
            if forceAll {
                await MainActor.run {
                    aiError = "No projects to analyze. All projects have been manually edited."
                }
            }
            return
        }
        
        await MainActor.run { isAIProcessing = true }
        
        do {
            // Process projects one by one with camera context
            var allCategorizations: [ProjectCategorization] = []
            
            for (index, project) in targetProjects.enumerated() {
                let result = try await geminiService.categorizeProjectWithContext(
                    project,
                    index: index + 1,
                    total: targetProjects.count,
                    existingClients: Array(clients)
                )
                
                if let cat = result {
                    allCategorizations.append(cat)
                    // Apply immediately so user sees progress
                    await MainActor.run {
                        applyCategorizations([cat], to: [project])
                    }
                }
            }
            
            let categorizedCount = allCategorizations.count
            await MainActor.run {
                geminiService.currentStep = "Categorized \(categorizedCount)/\(targetProjects.count) projects"
            }
            
            // Pass 2: Detect duplicates across all drives
            let allProjects = projects
            if allProjects.count > 1 {
                let duplicates = try await geminiService.detectDuplicates(allProjects: Array(allProjects))
                await MainActor.run {
                    applyDuplicateDetections(duplicates)
                }
                if !duplicates.isEmpty {
                    NotificationService.notifyDuplicatesFound(count: duplicates.count)
                }
            }
        } catch {
            await MainActor.run {
                aiError = error.localizedDescription
            }
        }
        
        await MainActor.run {
            isAIProcessing = false
            geminiService.currentStep = ""
            geminiService.status = .done
        }
    }
    
    private func applyCategorizations(_ categorizations: [ProjectCategorization], to projects: [Project]) {
        // Track clients created in this batch so we don't create duplicates
        // when `clients` @Query hasn't refreshed mid-loop.
        var newlyCreatedClients: [String: Client] = [:]
        
        for cat in categorizations {
            guard let project = projects.first(where: { $0.folderName == cat.folderName }) else { continue }
            guard !project.isEdited else { continue }
            
            project.projectType = cat.projectType
            project.aiSummary = cat.summary
            
            // Find or create client
            let clientName = cat.clientName
            let normalizedName = clientName.lowercased().trimmingCharacters(in: .whitespaces)
            
            if let existingClient = clients.first(where: { $0.name.lowercased().trimmingCharacters(in: .whitespaces) == normalizedName }) {
                project.client = existingClient
            } else if let batchClient = newlyCreatedClients[normalizedName] {
                // Reuse client created earlier in this same batch
                project.client = batchClient
            } else {
                let newClient = Client(name: clientName, aiConfidence: cat.confidence)
                modelContext.insert(newClient)
                newlyCreatedClients[normalizedName] = newClient
                project.client = newClient
            }
        }
        
        try? modelContext.save()
    }
    
    private func applyDuplicateDetections(_ detections: [DuplicateDetection]) {
        for detection in detections {
            var memberProjects: [Project] = []
            for memberString in detection.members {
                let parts = memberString.split(separator: ":/", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let folderPart = String(parts[1]).components(separatedBy: " (").first ?? String(parts[1])
                
                if let project = projects.first(where: { $0.folderName == folderPart }) {
                    memberProjects.append(project)
                }
            }
            
            guard memberProjects.count > 1 else { continue }
            
            let existingGroup = duplicateGroups.first { group in
                let groupProjectIds = Set(group.projects.map(\.id))
                let newProjectIds = Set(memberProjects.map(\.id))
                return !groupProjectIds.isDisjoint(with: newProjectIds)
            }
            
            if existingGroup == nil {
                let group = DuplicateGroup(
                    groupName: detection.groupName,
                    suggestedAction: detection.suggestedAction
                )
                
                let latestParts = detection.latestVersion.split(separator: ":/", maxSplits: 1)
                if latestParts.count == 2 {
                    let latestFolder = String(latestParts[1]).components(separatedBy: " (").first ?? String(latestParts[1])
                    group.latestVersionId = memberProjects.first(where: { $0.folderName == latestFolder })?.id
                }
                
                modelContext.insert(group)
                
                for project in memberProjects {
                    project.duplicateGroup = group
                }
            }
        }
        
        try? modelContext.save()
    }
}
