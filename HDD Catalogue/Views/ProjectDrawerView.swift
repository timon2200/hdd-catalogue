import SwiftUI
import SwiftData

/// Unified side drawer combining project details and inline editing.
/// Replaces the separate ProjectDetailView and ProjectEditView sheets.
struct ProjectDrawerView: View {
    @Bindable var project: Project
    @Binding var isPresented: Project?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(UndoManagerService.self) private var undoService
    
    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var allProjects: [Project]
    
    @State private var showNewClientField = false
    @State private var newClientName = ""
    
    private let projectTypes = [
        "Web Design", "Video Edit", "Photography", "3D/Motion",
        "Development", "Branding", "Music/Audio", "Documentation", "Other"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            drawerHeader
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Editable sections
                    statusAndClientSection
                    
                    // AI Summary (from categorization)
                    if !project.aiSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            drawerLabel("AI Summary", icon: "sparkles")
                            TextEditor(text: Binding(
                                get: { project.aiSummary },
                                set: {
                                    project.aiSummary = $0
                                    project.isEdited = true
                                    try? modelContext.save()
                                }
                            ))
                            .font(.callout)
                            .frame(minHeight: 40, maxHeight: 80)
                            .padding(6)
                            .background(Color.cyan.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.cyan.opacity(0.15), lineWidth: 0.5)
                            )
                        }
                    }
                    
                    tagsSection
                    notesSection
                    
                    Divider().padding(.horizontal)
                    
                    // Info sections
                    quickStatsSection
                    
                    if !project.detectedNLEs.isEmpty {
                        nleSection
                    }
                    
                    if let summary = project.mediaSummary, !summary.isEmpty {
                        mediaBreakdownSection(summary)
                    }
                    
                    if !project.cameraSources.isEmpty {
                        cameraSourcesSection
                    }
                    
                    if project.shootDayCount > 0 {
                        shootDaysSection
                    }
                    
                    projectStructureSection
                    
                    if project.isVisuallyIndexed {
                        visualContentSection
                    }
                    
                    // Deep Media File Tree
                    if project.isDeepIndexed {
                        FileTreeView(project: project)
                    } else if project.drive?.isConnected == true {
                        VStack(alignment: .leading, spacing: 6) {
                            drawerLabel("Files", icon: "doc.text.magnifyingglass")
                            Text("Not deep-indexed yet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Button {
                                Task {
                                    let service = DeepMediaSearchService()
                                    await service.deepIndexProject(project, modelContext: modelContext)
                                }
                            } label: {
                                Label("Deep Index This Project", systemImage: "square.stack.3d.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.cyan)
                        }
                    }
                    
                    Divider().padding(.horizontal)
                    
                    actionsSection
                    pathInfoSection
                }
                .padding(16)
            }
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(.quaternary).frame(width: 0.5)
        }
    }
    
    // MARK: - Header
    
    private var drawerHeader: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // Thumbnail
                projectThumbnail
                
                VStack(alignment: .leading, spacing: 4) {
                    // Editable display name
                    TextField("Project Name", text: Binding(
                        get: { project.displayName },
                        set: { newValue in
                            project.displayName = newValue
                            project.isEdited = true
                            try? modelContext.save()
                        }
                    ))
                    .font(.headline)
                    .textFieldStyle(.plain)
                    
                    // Folder name (read-only)
                    Text(project.folderName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    
                    // Drive info
                    if let drive = project.drive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(drive.isConnected ? .green : .gray)
                                .frame(width: 6, height: 6)
                            Text(drive.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Close button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isPresented = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
            }
            
            // Completeness bar
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                        Capsule()
                            .fill(completenessColor)
                            .frame(width: geo.size.width * project.projectCompleteness)
                            .animation(.spring(response: 0.5), value: project.projectCompleteness)
                    }
                }
                .frame(height: 4)
                
                Text("\(Int(project.projectCompleteness * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(completenessColor)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(16)
    }
    
    private var projectThumbnail: some View {
        Group {
            if let data = project.thumbnailData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var completenessColor: Color {
        switch project.projectCompleteness {
        case 0.9...1.0: return .green
        case 0.5..<0.9: return .yellow
        default:        return .orange
        }
    }
    
    // MARK: - Status & Client
    
    private var statusAndClientSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status picker
            HStack {
                drawerLabel("Status", icon: "circle.dotted")
                Spacer()
                Menu {
                    ForEach(ProjectStatus.allCases) { status in
                        Button {
                            project.projectStatus = status
                            try? modelContext.save()
                        } label: {
                            HStack {
                                Image(systemName: status.icon)
                                Text(status.rawValue)
                                if project.projectStatus == status {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: project.projectStatus.icon)
                            .font(.caption)
                            .foregroundStyle(project.projectStatus.color)
                        Text(project.projectStatus.rawValue)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(project.projectStatus.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            // Client picker
            HStack {
                drawerLabel("Client", icon: "person")
                Spacer()
                Menu {
                    Button {
                        project.client = nil
                        try? modelContext.save()
                    } label: {
                        HStack {
                            Text("Uncategorized")
                            if project.client == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    ForEach(clients, id: \.id) { client in
                        Button {
                            project.client = client
                            try? modelContext.save()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(client.color)
                                    .frame(width: 8, height: 8)
                                Text(client.name)
                                if project.client?.id == client.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(project.client?.color ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(project.client?.name ?? "Uncategorized")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            // Project type picker
            HStack {
                drawerLabel("Type", icon: "doc.text")
                Spacer()
                Menu {
                    ForEach(projectTypes, id: \.self) { type in
                        Button {
                            project.projectType = type
                            project.isEdited = true
                            try? modelContext.save()
                        } label: {
                            HStack {
                                Text(type)
                                if project.projectType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(project.projectType)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
    
    // MARK: - Tags
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            drawerLabel("Tags", icon: "tag")
            TagInputView(
                tags: Binding(
                    get: { project.tags },
                    set: {
                        project.tags = $0
                        try? modelContext.save()
                    }
                ),
                allTags: allExistingTags
            )
        }
    }
    
    // MARK: - Notes
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            drawerLabel("Notes", icon: "note.text")
            TextEditor(text: Binding(
                get: { project.notes },
                set: {
                    project.notes = $0
                    try? modelContext.save()
                }
            ))
            .font(.callout)
            .frame(minHeight: 60, maxHeight: 100)
            .padding(6)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if project.notes.isEmpty {
                    Text("Add notes…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
        }
    }
    
    // MARK: - Quick Stats
    
    private var quickStatsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 8) {
            miniStat(value: project.formattedSize, label: "Size", icon: "internaldrive", color: .blue)
            miniStat(value: "\(project.fileCount)", label: "Files", icon: "doc.fill", color: .purple)
            miniStat(value: project.formattedDate, label: "Modified", icon: "calendar", color: .orange)
            miniStat(value: project.isDelivered ? "Yes" : (project.hasExports ? "Partial" : "No"), label: "Delivered", icon: "checkmark.seal.fill", color: project.isDelivered ? .green : .gray)
        }
    }
    
    private func miniStat(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - NLE Section
    
    private var nleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            drawerLabel("NLE Projects", icon: "play.rectangle.fill")
            
            ForEach(project.nleIcons, id: \.name) { nle in
                HStack(spacing: 8) {
                    Image(systemName: nle.symbol)
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .frame(width: 14)
                    Text(nle.name)
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text(nle.abbreviation)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.purple)
                }
                .padding(8)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            }
            
            if let date = project.nleProjectFileDate {
                Text("Modified: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // MARK: - Media Breakdown
    
    private func mediaBreakdownSection(_ summary: MediaSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            drawerLabel("Media", icon: "chart.bar.fill")
            
            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    if summary.videoCount > 0 {
                        Color.blue.frame(width: segmentWidth(summary.videoCount, of: summary.totalCount, in: geo.size.width))
                    }
                    if summary.audioCount > 0 {
                        Color.green.frame(width: segmentWidth(summary.audioCount, of: summary.totalCount, in: geo.size.width))
                    }
                    if summary.graphicsCount > 0 {
                        Color.purple.frame(width: segmentWidth(summary.graphicsCount, of: summary.totalCount, in: geo.size.width))
                    }
                    if summary.fontCount > 0 {
                        Color.orange.frame(width: segmentWidth(summary.fontCount, of: summary.totalCount, in: geo.size.width))
                    }
                    if summary.renderCount > 0 {
                        Color.cyan.frame(width: segmentWidth(summary.renderCount, of: summary.totalCount, in: geo.size.width))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            
            // Legend
            VStack(spacing: 3) {
                if summary.videoCount > 0 { mediaRow("Video", count: summary.videoCount, color: .blue) }
                if summary.audioCount > 0 { mediaRow("Audio", count: summary.audioCount, color: .green) }
                if summary.graphicsCount > 0 { mediaRow("Graphics", count: summary.graphicsCount, color: .purple) }
                if summary.fontCount > 0 { mediaRow("Fonts", count: summary.fontCount, color: .orange) }
                if summary.renderCount > 0 { mediaRow("Renders", count: summary.renderCount, color: .cyan) }
            }
        }
    }
    
    private func segmentWidth(_ count: Int, of total: Int, in width: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(3, (CGFloat(count) / CGFloat(total)) * width)
    }
    
    private func mediaRow(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2)
            Spacer()
            Text("\(count)").font(.caption2).foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Camera Sources
    
    private var cameraSourcesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            drawerLabel("Cameras", icon: "camera.fill")
            
            FlowLayoutCompact(spacing: 6) {
                ForEach(project.cameraSources, id: \.self) { camera in
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 8))
                        Text(camera)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.1), in: Capsule())
                    .foregroundStyle(.indigo)
                }
                
                if project.hasDroneFootage {
                    HStack(spacing: 4) {
                        Image(systemName: "airplane")
                            .font(.system(size: 8))
                        Text("Drone")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.1), in: Capsule())
                    .foregroundStyle(.cyan)
                }
            }
        }
    }
    
    // MARK: - Shoot Days
    
    private var shootDaysSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            drawerLabel("Shoot Days (\(project.shootDayCount))", icon: "calendar.badge.clock")
            
            ForEach(project.shootDayFolders, id: \.self) { folder in
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(folder)
                        .font(.caption)
                }
            }
        }
    }
    
    // MARK: - Project Structure
    
    private var projectStructureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            drawerLabel("Checklist", icon: "checklist")
            
            checkRow("Source Footage", done: project.mediaSummary?.videoCount ?? 0 > 0 || !project.cameraSources.isEmpty)
            checkRow("NLE Project", done: !project.detectedNLEs.isEmpty)
            checkRow("Exports", done: project.hasExports)
        }
    }
    
    private func checkRow(_ label: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(done ? .green : Color.gray.opacity(0.3))
            Text(label)
                .font(.caption)
                .foregroundStyle(done ? .primary : .secondary)
        }
    }
    
    // MARK: - Actions
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            drawerLabel("Actions", icon: "gearshape")
            
            if project.drive?.isConnected == true && (project.mediaSummary?.videoCount ?? 0 > 0) {
                Button {
                    Task {
                        let projectURL = URL(fileURLWithPath: project.folderPath)
                        if let data = await VideoThumbnailService.generateThumbnail(for: projectURL) {
                            project.thumbnailData = data
                            project.thumbnailType = .videoFrame
                            try? modelContext.save()
                        }
                    }
                } label: {
                    Label("Regenerate Thumbnail", systemImage: "photo.on.rectangle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Visual Content
    
    private var visualContentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            drawerLabel("Visual Content", icon: "eye.fill")
            
            // Visual description
            if !project.visualDescription.isEmpty {
                Text(project.visualDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            }
            
            // Visual tags
            if !project.visualTags.isEmpty {
                FlowLayoutCompact(spacing: 4) {
                    ForEach(project.visualTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.purple.opacity(0.1), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }
            }
            
            // Find Similar button
            Button {
                NotificationCenter.default.post(
                    name: .findSimilarProject,
                    object: project.id
                )
            } label: {
                Label("Find Similar Projects", systemImage: "sparkle.magnifyingglass")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.purple)
        }
    }
    
    // MARK: - Path Info
    
    private var pathInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            drawerLabel("Location", icon: "folder")
            
            Text(project.folderPath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(3)
            
            if project.drive?.isConnected == true {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.folderPath)
                } label: {
                    Label("Show in Finder", systemImage: "arrow.right.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Helpers
    
    private func drawerLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
    
    private var allExistingTags: [String] {
        Array(Set(allProjects.flatMap(\.tags))).sorted()
    }
}

// MARK: - Compact Flow Layout

struct FlowLayoutCompact: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        
        return CGSize(width: maxWidth, height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
