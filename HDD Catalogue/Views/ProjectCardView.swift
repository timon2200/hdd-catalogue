import SwiftUI
import UniformTypeIdentifiers

/// Individual project card with thumbnail, client color accent, and interactive features.
struct ProjectCardView: View {
    let project: Project
    let onEdit: () -> Void
    let onChangeThumbnail: () -> Void
    
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card body
            HStack(alignment: .top, spacing: 0) {
                // Client color accent strip
                RoundedRectangle(cornerRadius: 2)
                    .fill(project.client?.color ?? .gray.opacity(0.5))
                    .frame(width: 4)
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 10) {
                    // Header: thumbnail + name
                    HStack(spacing: 10) {
                        thumbnailView
                            .frame(width: 40, height: 40)
                            .onTapGesture { onChangeThumbnail() }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.displayName)
                                .font(.headline)
                                .lineLimit(1)
                            
                            if let driveName = project.drive?.name {
                                HStack(spacing: 4) {
                                    Image(systemName: project.drive?.isConnected == true ? "externaldrive.fill" : "externaldrive")
                                        .font(.caption2)
                                        .foregroundStyle(project.drive?.isConnected == true ? .green : .gray)
                                    Text(driveName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Duplicate badge
                        if project.duplicateGroup != nil && !(project.duplicateGroup?.isDismissed ?? true) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                                .help("Duplicate project detected")
                        }
                    }
                    
                    // Metadata row
                    HStack(spacing: 12) {
                        // Size
                        Label(project.formattedSize, systemImage: "doc.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // File count
                        Label("\(project.fileCount) files", systemImage: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        // Date
                        Text(project.formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Project type tag + client
                    HStack(spacing: 8) {
                        // Type badge
                        Text(project.projectType)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (project.client?.color ?? .gray).opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(project.client?.color ?? .gray)
                        
                        if let clientName = project.client?.name {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(project.client?.color ?? .gray)
                                    .frame(width: 6, height: 6)
                                Text(clientName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if project.isEdited {
                            Image(systemName: "pencil.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .help("Manually edited")
                        }
                    }
                    
                    // AI Summary
                    if !project.aiSummary.isEmpty {
                        Text(project.aiSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(12)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(
                    color: .black.opacity(isHovering ? 0.2 : 0.1),
                    radius: isHovering ? 12 : 6,
                    y: isHovering ? 4 : 2
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDropTargeted ? Color.blue : (isHovering ? Color.primary.opacity(0.1) : .clear),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        }
        // Disconnected drive dimming
        .opacity(project.drive?.isConnected == false ? 0.55 : 1.0)
        .overlay {
            if project.drive?.isConnected == false {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "eject.fill")
                            .font(.caption)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onEdit()
        }
        .contextMenu {
            Button("Edit Project") { onEdit() }
            Button("Change Thumbnail") { onChangeThumbnail() }
            Divider()
            if project.drive?.isConnected == true {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.folderPath)
                }
            }
        }
        // Drop image for thumbnail
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleImageDrop(providers)
        }
    }
    
    // MARK: - Thumbnail View
    
    @ViewBuilder
    private var thumbnailView: some View {
        switch project.thumbnailType {
        case .image:
            if let data = project.thumbnailData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                autoThumbnail
            }
        case .emoji:
            Text(project.resolvedThumbnailEmoji)
                .font(.system(size: 28))
                .frame(width: 40, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        case .icon:
            Image(systemName: project.thumbnailIconName ?? ThumbnailManager.defaultSFSymbol(for: project.projectType))
                .font(.system(size: 20))
                .foregroundStyle(project.client?.color ?? .gray)
                .frame(width: 40, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        case .auto:
            autoThumbnail
        }
    }
    
    private var autoThumbnail: some View {
        Text(project.autoThumbnailEmoji)
            .font(.system(size: 28))
            .frame(width: 40, height: 40)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Drag & Drop
    
    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data = data, let thumbnailData = ThumbnailManager.processDroppedImage(data) {
                        DispatchQueue.main.async {
                            project.thumbnailData = thumbnailData
                            project.thumbnailType = .image
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
                            try? modelContext.save()
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}
