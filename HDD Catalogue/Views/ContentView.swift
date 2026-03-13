import SwiftUI
import SwiftData

/// Main content view with NavigationSplitView — sidebar + detail grid.
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
    
    private let geminiService = GeminiService()
    
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
            result = result.filter {
                $0.displayName.lowercased().contains(query) ||
                $0.folderName.lowercased().contains(query) ||
                $0.projectType.lowercased().contains(query) ||
                $0.aiSummary.lowercased().contains(query) ||
                ($0.client?.name.lowercased().contains(query) ?? false) ||
                ($0.drive?.name.lowercased().contains(query) ?? false)
            }
        }
        
        return result.sorted { ($0.dateModified ?? .distantPast) > ($1.dateModified ?? .distantPast) }
    }
    
    var activeDuplicates: [DuplicateGroup] {
        duplicateGroups.filter { !$0.isDismissed && $0.projects.count > 1 }
    }
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                drives: drives,
                clients: clients,
                selectedDrive: $selectedDrive,
                selectedClient: $selectedClient,
                scanEngine: scanEngine,
                duplicateCount: activeDuplicates.count,
                showDuplicates: $showDuplicates,
                onScanDrive: { drive in
                    Task { await scanAndCategorize(drive: drive) }
                },
                onScanAll: {
                    Task { await scanAllDrives() }
                }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ZStack {
                CatalogueGridView(
                    projects: filteredProjects,
                    clients: clients,
                    searchText: $searchText,
                    selectedClient: $selectedClient,
                    isAIProcessing: isAIProcessing
                )
                
                // Scan progress overlay
                if scanEngine.isScanning {
                    ScanProgressView(scanEngine: scanEngine)
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
            }
            .animation(.spring(response: 0.4), value: showDuplicates)
        }
        .searchable(text: $searchText, prompt: "Search projects, clients, drives…")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if isAIProcessing {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI analyzing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !activeDuplicates.isEmpty {
                    Button {
                        showDuplicates.toggle()
                    } label: {
                        Label("Duplicates (\(activeDuplicates.count))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
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
        driveMonitor.startMonitoring(
            modelContext: modelContext,
            scanEngine: scanEngine
        ) { drive in
            // Auto-scan on mount
            Task { await scanAndCategorize(drive: drive) }
        }
    }
    
    private func scanAllDrives() async {
        let connectedDrives = drives.filter(\.isConnected)
        for drive in connectedDrives {
            await scanAndCategorize(drive: drive)
        }
    }
    
    private func scanAndCategorize(drive: Drive) async {
        // Step 1: Scan folders
        let scannedProjects = await scanEngine.scanDrive(drive, modelContext: modelContext)
        
        // Insert new projects
        for project in scannedProjects where project.drive == nil {
            project.drive = drive
            modelContext.insert(project)
        }
        try? modelContext.save()
        
        // Step 2: AI categorization (only for uncategorized or un-edited projects)
        let needsCategorization = scannedProjects.filter { !$0.isEdited && $0.projectType == "Unknown" }
        
        guard !needsCategorization.isEmpty else { return }
        guard KeychainHelper.hasAPIKey else {
            await MainActor.run {
                aiError = "No Gemini API key configured. Please add your key in Settings to enable AI categorization."
            }
            return
        }
        
        await MainActor.run { isAIProcessing = true }
        
        do {
            // Pass 1: Categorize
            let categorizations = try await geminiService.categorizeProjects(needsCategorization, existingClients: clients)
            
            await MainActor.run {
                applyCategorizations(categorizations, to: scannedProjects)
            }
            
            // Pass 2: Detect duplicates across all drives
            let allProjects = projects
            if allProjects.count > 1 {
                let duplicates = try await geminiService.detectDuplicates(allProjects: Array(allProjects))
                await MainActor.run {
                    applyDuplicateDetections(duplicates)
                }
            }
        } catch {
            await MainActor.run {
                aiError = error.localizedDescription
            }
        }
        
        await MainActor.run { isAIProcessing = false }
    }
    
    private func applyCategorizations(_ categorizations: [ProjectCategorization], to projects: [Project]) {
        for cat in categorizations {
            guard let project = projects.first(where: { $0.folderName == cat.folderName }) else { continue }
            guard !project.isEdited else { continue }
            
            project.projectType = cat.projectType
            project.aiSummary = cat.summary
            
            // Find or create client
            let clientName = cat.clientName
            if let existingClient = clients.first(where: { $0.name.lowercased() == clientName.lowercased() }) {
                project.client = existingClient
            } else {
                let newClient = Client(name: clientName, aiConfidence: cat.confidence)
                modelContext.insert(newClient)
                project.client = newClient
            }
        }
        
        try? modelContext.save()
    }
    
    private func applyDuplicateDetections(_ detections: [DuplicateDetection]) {
        for detection in detections {
            // Find member projects
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
            
            // Check if a duplicate group already exists for these projects
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
                
                // Find latest version
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
