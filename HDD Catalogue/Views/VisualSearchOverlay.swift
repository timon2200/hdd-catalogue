import SwiftUI
import SwiftData

/// AI Visual Search overlay — ⌘⇧F
/// Searches across project visual content (thumbnails) and metadata using natural language.
struct VisualSearchOverlay: View {
    @Binding var isPresented: Bool
    let visualSearchService: VisualSearchService
    
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]
    
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var searchMode: SearchMode = .visual
    @State private var results: [VisualSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @FocusState private var isSearchFocused: Bool
    
    // Debounce for visual tag search
    @State private var debounceTask: Task<Void, Never>?
    
    enum SearchMode: String, CaseIterable {
        case visual = "Visual"
        case smart = "Smart"
        
        var icon: String {
            switch self {
            case .visual: return "eye.fill"
            case .smart: return "brain"
            }
        }
        
        var placeholder: String {
            switch self {
            case .visual: return "sunset, interview, aerial, underwater…"
            case .smart: return "all Premiere projects from last month over 10GB…"
            }
        }
    }
    
    var matchedProjects: [(project: Project, result: VisualSearchResult)] {
        results.compactMap { result in
            guard let project = projects.first(where: { $0.id == result.projectId }) else { return nil }
            return (project, result)
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
                // Header with mode toggles
                HStack(spacing: 12) {
                    Image(systemName: searchMode.icon)
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
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
                            if searchMode == .visual {
                                // Debounce visual tag search
                                debounceTask?.cancel()
                                debounceTask = Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    guard !Task.isCancelled else { return }
                                    results = visualSearchService.visualSearch(query: newValue, projects: Array(projects))
                                }
                            }
                        }
                    
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
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
                    
                    // Mode toggles
                    Picker("", selection: $searchMode) {
                        ForEach(SearchMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .onChange(of: searchMode) { _, _ in
                        results = []
                        errorMessage = nil
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
                
                // Content
                if query.isEmpty && results.isEmpty {
                    emptyStateView
                } else if isSearching {
                    searchingStateView
                } else if let error = errorMessage {
                    errorStateView(error)
                } else if results.isEmpty && !query.isEmpty {
                    noResultsView
                } else {
                    resultsListView
                }
                
                // Footer
                if !matchedProjects.isEmpty {
                    Divider()
                    HStack {
                        Text("\(matchedProjects.count) result\(matchedProjects.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if searchMode == .smart {
                            Text("Powered by Gemini")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        shortcutHint("↩", "Open")
                        shortcutHint("esc", "Close")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .frame(width: 640)
            .frame(maxHeight: 520)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.2), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .purple.opacity(0.15), radius: 40, y: 10)
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
            if selectedIndex < matchedProjects.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onKeyPress(.return) {
            if searchMode == .smart && results.isEmpty && !query.isEmpty {
                performSearch()
            } else {
                openSelected()
            }
            return .handled
        }
    }
    
    // MARK: - State Views
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("AI Visual Search")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text(searchMode == .visual
                 ? "Search by visual content — moods, scenes, objects"
                 : "Ask anything about your projects in natural language")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                if searchMode == .visual {
                    exampleChip("sunset")
                    exampleChip("interview")
                    exampleChip("aerial")
                    exampleChip("nature")
                } else {
                    exampleChip("Premiere projects this month")
                    exampleChip("large undelivered projects")
                }
            }
            .padding(.top, 4)
            
            let indexedCount = projects.filter(\.isVisuallyIndexed).count
            if indexedCount > 0 {
                Text("\(indexedCount) of \(projects.count) projects visually indexed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
    
    private var searchingStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text(visualSearchService.currentStep.isEmpty ? "Searching…" : visualSearchService.currentStep)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
    
    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { performSearch() }
                .buttonStyle(.bordered)
                .padding(.top, 4)
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
            
            Text("No results for \"\(query)\"")
                .foregroundStyle(.secondary)
            
            if searchMode == .visual {
                let indexedCount = projects.filter(\.isVisuallyIndexed).count
                if indexedCount == 0 {
                    Text("No projects have been visually indexed yet.\nRun a scan to index project thumbnails.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Try different keywords or switch to Smart mode for metadata queries")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Press ↩ to search with AI")
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
                    ForEach(Array(matchedProjects.enumerated()), id: \.element.project.id) { index, item in
                        resultRow(item.project, result: item.result, isSelected: index == selectedIndex)
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
    private func resultRow(_ project: Project, result: VisualSearchResult, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let data = project.thumbnailData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Text(project.resolvedThumbnailEmoji)
                        .font(.title2)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary, lineWidth: 1)
            )
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if let client = project.client {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(client.color)
                                .frame(width: 6, height: 6)
                            Text(client.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text(result.reason)
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Relevance indicator
            let percentage = Int(result.relevance * 100)
            Text("\(percentage)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.purple.opacity(0.12), in: Capsule())
            
            // Drive
            if let drive = project.drive {
                HStack(spacing: 3) {
                    Image(systemName: drive.isConnected ? "externaldrive.fill" : "externaldrive")
                        .font(.system(size: 9))
                        .foregroundStyle(drive.isConnected ? .green : .gray)
                    Text(drive.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected
            ? Color.purple.opacity(0.12)
            : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
    
    // MARK: - Helper Views
    
    private func exampleChip(_ text: String) -> some View {
        Button {
            query = text
            if searchMode == .visual {
                results = visualSearchService.visualSearch(query: text, projects: Array(projects))
            } else {
                performSearch()
            }
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.purple.opacity(0.1), in: Capsule())
                .foregroundStyle(.purple)
        }
        .buttonStyle(.plain)
    }
    
    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        guard !query.isEmpty else { return }
        
        if searchMode == .visual {
            results = visualSearchService.visualSearch(query: query, projects: Array(projects))
        } else {
            // Smart mode: use Gemini NL query
            isSearching = true
            errorMessage = nil
            Task {
                do {
                    let searchResults = try await visualSearchService.naturalLanguageSearch(
                        query: query,
                        projects: Array(projects)
                    )
                    await MainActor.run {
                        results = searchResults
                        isSearching = false
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isSearching = false
                    }
                }
            }
        }
    }
    
    private func openSelected() {
        guard selectedIndex < matchedProjects.count else { return }
        let project = matchedProjects[selectedIndex].project
        NotificationCenter.default.post(
            name: .openProjectDetail,
            object: project.id
        )
        close()
    }
    
    private func close() {
        withAnimation(.easeOut(duration: 0.15)) {
            isPresented = false
        }
    }
}
