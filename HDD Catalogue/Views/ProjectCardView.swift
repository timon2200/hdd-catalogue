import SwiftUI
import UniformTypeIdentifiers

/// Premium project card matching the reference design: large hero thumbnail,
/// inline badges, overlaid delivered badge, blue-tinted dark background.
struct ProjectCardView: View {
    let project: Project
    let onEdit: () -> Void
    let onChangeThumbnail: () -> Void
    let onShowDetail: () -> Void
    var onOpenExplorer: (() -> Void)? = nil
    
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var cachedImage: NSImage?
    @Environment(\.modelContext) private var modelContext
    @Environment(UndoManagerService.self) private var undoService
    
    // Card colors
    private let cardBackground = Color(red: 0.12, green: 0.15, blue: 0.22)
    private let cardBorder = Color(red: 0.22, green: 0.26, blue: 0.35)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Hero Thumbnail ──
            heroThumbnail
            
            // ── Content ──
            VStack(alignment: .leading, spacing: 8) {
                
                // Row 1: Status + Project Name + NLE/Camera/Media badges
                HStack(alignment: .center, spacing: 6) {
                    // Status indicator
                    Image(systemName: project.projectStatus.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(project.projectStatus.color)
                        .help(project.projectStatus.rawValue)
                    
                    Text(project.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // NLE badges
                    ForEach(project.nleIcons, id: \.name) { nle in
                        badgePill(nle.abbreviation, color: .purple)
                    }
                    
                    // Camera badges
                    ForEach(project.cameraSources.prefix(2), id: \.self) { camera in
                        badgePill(camera, color: .indigo)
                    }
                    
                    // Dominant media type
                    if let summary = project.mediaSummary, !summary.isEmpty {
                        let (_, color) = mediaInfo(summary.dominantType)
                        badgePill(summary.dominantType, color: color)
                    }
                }
                
                // Row 2: Drive name
                if let driveName = project.drive?.name {
                    HStack(spacing: 4) {
                        Image(systemName: project.drive?.isConnected == true ? "externaldrive.fill" : "externaldrive")
                            .font(.system(size: 9))
                            .foregroundStyle(project.drive?.isConnected == true ? .green : .gray)
                        Text(driveName)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                
                // Row 3: Metadata — size · files · date
                HStack(spacing: 14) {
                    metaItem(icon: "doc.fill", text: project.formattedSize)
                    metaItem(icon: "person.2.fill", text: "\(project.fileCount)")
                    metaItem(icon: "calendar", text: project.formattedDate)
                    Spacer()
                }
                
                // Row 4: Client + Delivery info
                HStack {
                    if let client = project.client {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(client.color)
                                .frame(width: 8, height: 8)
                            Text(client.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(white: 0.75))
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    if project.isDelivered || project.hasExports {
                        Text(project.isDelivered ? "DELIVERED" : "HAS EXPORTS")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(project.isDelivered ? Color.green.opacity(0.7) : Color.orange.opacity(0.6))
                    }
                }
                
                // Row 5: AI Summary + completeness
                HStack(alignment: .bottom) {
                    if !project.aiSummary.isEmpty {
                        Text(project.aiSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.45))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                    }
                    
                    // Completeness ring
                    if project.projectCompleteness > 0 {
                        completenessRing
                    }
                }
                
                // Row 6: Tags
                if !project.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(project.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(TagColorHelper.color(for: tag).opacity(0.15), in: Capsule())
                                .foregroundStyle(TagColorHelper.color(for: tag))
                        }
                        if project.tags.count > 3 {
                            Text("+\(project.tags.count - 3)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }
                }
                
                // Row 7: Visual tags (AI-generated)
                if !project.visualTags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.purple.opacity(0.5))
                        ForEach(project.visualTags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.purple.opacity(0.1), in: Capsule())
                                .foregroundStyle(.purple.opacity(0.7))
                        }
                        if project.visualTags.count > 3 {
                            Text("+\(project.visualTags.count - 3)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isDropTargeted ? Color.blue.opacity(0.6) :
                    isHovering ? cardBorder : cardBorder.opacity(0.5),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        }
        .compositingGroup()
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovering ? 0.35 : 0.25), radius: isHovering ? 14 : 8, y: isHovering ? 7 : 4)
        .opacity(project.drive?.isConnected == false ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
        .onTapGesture(count: 2) { if let onOpenExplorer { onOpenExplorer() } else { onShowDetail() } }
        .onTapGesture { onShowDetail() }
        .contextMenu { contextMenuContent }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { handleImageDrop($0) }
        .onAppear { cacheImage() }
        .onChange(of: project.thumbnailData) { _, _ in cacheImage() }
    }
    
    // MARK: - Hero Thumbnail
    
    private var heroThumbnail: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail image
            Group {
                switch project.thumbnailType {
                case .image, .videoFrame:
                    if let nsImage = cachedImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else {
                        placeholderGradient
                    }
                case .emoji:
                    emojiPlaceholder(project.resolvedThumbnailEmoji)
                case .icon:
                    iconPlaceholder
                case .auto:
                    if project.mediaSummary?.videoCount ?? 0 > 0 {
                        cinemaGradient
                    } else {
                        emojiPlaceholder(project.autoThumbnailEmoji)
                    }
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(Rectangle())
            
            // Delivered overlay badge (top-right of thumbnail)
            if project.isDelivered {
                Text("Delivered")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .padding(10)
            }
            
            // Duplicate warning overlay
            if project.duplicateGroup != nil && !(project.duplicateGroup?.isDismissed ?? true) {
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 14))
                            .shadow(radius: 4)
                            .padding(10)
                        Spacer()
                    }
                    Spacer()
                }
            }
            
            // Disconnected overlay
            if project.drive?.isConnected == false {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "eject.fill")
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(10)
                    }
                }
            }
            
            // Pinned/favorite badge (bottom-left)
            if project.isFavorite {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(8)
                        Spacer()
                    }
                }
            }
        }

    }
    
    // MARK: - Thumbnail Variants
    
    private var placeholderGradient: some View {
        LinearGradient(
            colors: [cardBackground.opacity(0.8), Color.gray.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
        }
    }
    
    private var cinemaGradient: some View {
        LinearGradient(
            colors: [
                (project.client?.color ?? .purple).opacity(0.35),
                cardBackground
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "film")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.15))
        }
    }
    
    private func emojiPlaceholder(_ emoji: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    (project.client?.color ?? .gray).opacity(0.12),
                    cardBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(emoji)
                .font(.system(size: 52))
        }
    }
    
    private var iconPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    (project.client?.color ?? .blue).opacity(0.15),
                    cardBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: project.thumbnailIconName ?? ThumbnailManager.defaultSFSymbol(for: project.projectType))
                .font(.system(size: 36))
                .foregroundStyle(project.client?.color ?? .blue)
        }
    }
    
    // MARK: - Shared Components
    
    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(color)
    }
    
    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.4))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.5))
        }
    }
    
    private func mediaInfo(_ type: String) -> (icon: String, color: Color) {
        switch type {
        case "Video":    return ("video.fill", .blue)
        case "Audio":    return ("waveform", .green)
        case "Graphics": return ("photo.fill", .purple)
        case "Fonts":    return ("textformat", .orange)
        case "Renders":  return ("film", .cyan)
        default:         return ("doc.fill", .gray)
        }
    }
    
    // MARK: - Completeness Ring
    
    private var completenessRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: project.projectCompleteness)
                .stroke(completenessColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(project.projectCompleteness * 100))")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
        }
        .frame(width: 28, height: 28)
        .help(completenessLabel)
    }
    
    private var completenessColor: Color {
        switch project.projectCompleteness {
        case 0.9...1.0: return .green
        case 0.5..<0.9: return .yellow
        default:        return .orange
        }
    }
    
    private var completenessLabel: String {
        let pct = Int(project.projectCompleteness * 100)
        var parts: [String] = []
        if !project.detectedNLEs.isEmpty { parts.append("NLE ✓") }
        if project.mediaSummary?.videoCount ?? 0 > 0 { parts.append("Sources ✓") }
        if project.hasExports { parts.append("Exports ✓") }
        return "\(pct)% — \(parts.isEmpty ? "No data" : parts.joined(separator: ", "))"
    }
    
    // MARK: - Image Caching
    
    private func cacheImage() {
        if let data = project.thumbnailData {
            cachedImage = NSImage(data: data)
        } else {
            cachedImage = nil
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button("Edit Project") { onEdit() }
        Button("Change Thumbnail") { onChangeThumbnail() }
        Button("Project Details") { onShowDetail() }
        Divider()
        
        // Status submenu
        Menu("Set Status") {
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
        }
        
        Divider()
        if project.drive?.isConnected == true {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.folderPath)
            }
        }
        
        Divider()
        Button(project.isFavorite ? "Unpin" : "Pin to Top") {
            project.isFavorite.toggle()
            try? modelContext.save()
        }
        
        if project.isVisuallyIndexed {
            Divider()
            Button("Find Similar") {
                NotificationCenter.default.post(
                    name: .findSimilarProject,
                    object: project.id
                )
            }
        }
    }
    

    
    // MARK: - Drag & Drop
    
    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        let oldSnapshot = UndoManagerService.ThumbnailSnapshot(
            thumbnailTypeRaw: project.thumbnailTypeRaw,
            thumbnailData: project.thumbnailData,
            thumbnailEmoji: project.thumbnailEmoji,
            thumbnailIconName: project.thumbnailIconName
        )
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data = data, let thumbnailData = ThumbnailManager.processDroppedImage(data) {
                        DispatchQueue.main.async {
                            project.thumbnailData = thumbnailData
                            project.thumbnailType = .image
                            registerThumbnailUndo(oldSnapshot: oldSnapshot)
                            try? modelContext.save()
                        }
                    }
                }
                return true
            }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       let thumbnailData = ThumbnailManager.processImageFile(url) {
                        DispatchQueue.main.async {
                            project.thumbnailData = thumbnailData
                            project.thumbnailType = .image
                            registerThumbnailUndo(oldSnapshot: oldSnapshot)
                            try? modelContext.save()
                        }
                    }
                }
                return true
            }
        }
        return false
    }
    
    private func registerThumbnailUndo(oldSnapshot: UndoManagerService.ThumbnailSnapshot) {
        let newSnapshot = UndoManagerService.ThumbnailSnapshot(
            thumbnailTypeRaw: project.thumbnailTypeRaw,
            thumbnailData: project.thumbnailData,
            thumbnailEmoji: project.thumbnailEmoji,
            thumbnailIconName: project.thumbnailIconName
        )
        undoService.registerThumbnailChange(
            project: project,
            oldSnapshot: oldSnapshot,
            newSnapshot: newSnapshot,
            context: modelContext
        )
    }
}
