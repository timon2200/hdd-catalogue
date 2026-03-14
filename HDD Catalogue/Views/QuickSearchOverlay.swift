import SwiftUI
import SwiftData

/// Spotlight-style ⌘K quick search overlay.
/// Searches across all project fields regardless of drive connection status.
struct QuickSearchOverlay: View {
    @Binding var isPresented: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]
    @Query private var clients: [Client]
    @Query private var drives: [Drive]
    
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    
    private var results: [SearchResult] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        
        return projects
            .filter { project in
                project.displayName.lowercased().contains(q) ||
                project.folderName.lowercased().contains(q) ||
                project.projectType.lowercased().contains(q) ||
                project.aiSummary.lowercased().contains(q) ||
                (project.client?.name.lowercased().contains(q) ?? false) ||
                (project.drive?.name.lowercased().contains(q) ?? false) ||
                project.detectedNLEs.contains(where: { $0.lowercased().contains(q) }) ||
                project.cameraSources.contains(where: { $0.lowercased().contains(q) }) ||
                project.tags.contains(where: { $0.lowercased().contains(q) }) ||
                project.notes.lowercased().contains(q) ||
                project.projectStatus.rawValue.lowercased().contains(q)
            }
            .sorted { ($0.projectDate ?? .distantPast) > ($1.projectDate ?? .distantPast) }
            .prefix(12)
            .map { SearchResult(project: $0) }
    }
    
    struct SearchResult: Identifiable {
        let project: Project
        var id: UUID { project.id }
    }
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }
            
            // Search panel
            VStack(spacing: 0) {
                // Search input
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    
                    TextField("Search projects, clients, tags, cameras…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($isSearchFocused)
                        .onSubmit {
                            openSelected()
                        }
                    
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Text("⌘K")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
                
                // Results
                if query.isEmpty {
                    // Hint
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("Type to search across all drives")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            shortcutHint("↑↓", "Navigate")
                            shortcutHint("↩", "Open")
                            shortcutHint("⌘↩", "Show in Finder")
                            shortcutHint("esc", "Close")
                        }
                        .padding(.top, 4)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else if results.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("No results for \"\(query)\"")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                    resultRow(result, isSelected: index == selectedIndex)
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
                
                // Footer
                if !results.isEmpty {
                    Divider()
                    HStack {
                        Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        shortcutHint("↩", "Open")
                        shortcutHint("⌘↩", "Finder")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .frame(width: 600)
            .frame(maxHeight: 480)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.quaternary, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
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
    
    // MARK: - Result Row
    
    @ViewBuilder
    private func resultRow(_ result: SearchResult, isSelected: Bool) -> some View {
        let project = result.project
        
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: project.projectStatus.icon)
                .font(.caption)
                .foregroundStyle(project.projectStatus.color)
                .frame(width: 16)
            
            // Client color dot
            Circle()
                .fill(project.client?.color ?? .gray)
                .frame(width: 8, height: 8)
            
            // Project info
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let client = project.client {
                        Text(client.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(project.projectType)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    if !project.tags.isEmpty {
                        Text(project.tags.prefix(2).joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                }
            }
            
            Spacer()
            
            // NLE badges
            ForEach(project.nleIcons.prefix(2), id: \.name) { nle in
                Text(nle.abbreviation)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.purple)
            }
            
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
            
            Text(project.formattedSize)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected
            ? Color.accentColor.opacity(0.15)
            : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
    
    // MARK: - Shortcut Hints
    
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
    
    private func openSelected() {
        guard selectedIndex < results.count else { return }
        let project = results[selectedIndex].project
        // Post notification to open project detail
        NotificationCenter.default.post(
            name: .openProjectDetail,
            object: project.id
        )
        close()
    }
    
    private func revealInFinder() {
        guard selectedIndex < results.count else { return }
        let project = results[selectedIndex].project
        if project.drive?.isConnected == true {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.folderPath)
        }
        close()
    }
    
    private func close() {
        withAnimation(.easeOut(duration: 0.15)) {
            isPresented = false
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let openProjectDetail = Notification.Name("openProjectDetail")
    static let toggleQuickSearch = Notification.Name("toggleQuickSearch")
    static let toggleVisualSearch = Notification.Name("toggleVisualSearch")
    static let findSimilarProject = Notification.Name("findSimilarProject")
    static let toggleDeepMediaSearch = Notification.Name("toggleDeepMediaSearch")
}
