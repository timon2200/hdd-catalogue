import SwiftUI
import SwiftData

/// Expandable file tree for a deep-indexed project.
/// Groups files by category (Video, Audio, Images, Project Files, Other)
/// and shows metadata badges for each file.
struct FileTreeView: View {
    let project: Project
    
    @State private var expandedCategories: Set<String> = ["Video"]
    @State private var selectedFile: MediaFile?
    @State private var showFileExplorer = false
    @State private var explorerFile: MediaFile?
    
    private var groupedFiles: [(category: MediaFileType, files: [MediaFile])] {
        let groups = Dictionary(grouping: project.mediaFiles) { $0.fileType }
        return MediaFileType.allCases.compactMap { type in
            guard let files = groups[type], !files.isEmpty else { return nil }
            return (category: type, files: files.sorted { $0.filename < $1.filename })
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Summary header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Files")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(project.mediaFiles.count) files indexed")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            // Category groups
            ForEach(groupedFiles, id: \.category) { group in
                categorySection(group.category, files: group.files)
            }
            
            // Deep index date
            if let date = project.lastDeepIndexDate {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 8))
                        .foregroundStyle(.gray.opacity(0.4))
                    Text("Indexed: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(.gray.opacity(0.4))
                }
                .padding(.top, 2)
            }
            
            // File detail panel (if selected)
            if let file = selectedFile {
                fileDetailPanel(file)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .sheet(isPresented: $showFileExplorer) {
            if let file = explorerFile {
                MediaFileExplorerView(
                    project: project,
                    initialFile: file,
                    isPresented: $showFileExplorer
                )
            }
        }
    }
    
    // MARK: - Category Section
    
    @ViewBuilder
    private func categorySection(_ category: MediaFileType, files: [MediaFile]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if expandedCategories.contains(category.rawValue) {
                        expandedCategories.remove(category.rawValue)
                    } else {
                        expandedCategories.insert(category.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expandedCategories.contains(category.rawValue) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    
                    Image(systemName: categoryIcon(category))
                        .font(.system(size: 10))
                        .foregroundStyle(categoryColor(category))
                    
                    Text(category.rawValue)
                        .font(.system(size: 11, weight: .medium))
                    
                    Spacer()
                    
                    Text("\(files.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.2), in: Capsule())
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .background(Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded file list
            if expandedCategories.contains(category.rawValue) {
                VStack(spacing: 1) {
                    ForEach(files.prefix(100), id: \.id) { file in
                        fileRow(file)
                    }
                    
                    if files.count > 100 {
                        Text("+ \(files.count - 100) more files")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                            .padding(.leading, 28)
                    }
                }
                .padding(.leading, 10)
            }
        }
    }
    
    // MARK: - File Row
    
    private func fileRow(_ file: MediaFile) -> some View {
        Button {
            withAnimation(.spring(response: 0.25)) {
                selectedFile = selectedFile?.id == file.id ? nil : file
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: file.typeIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(categoryColor(file.fileType))
                    .frame(width: 14)
                
                Text(file.filename)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                if !file.metadataBadge.isEmpty {
                    Text(file.metadataBadge)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                }
                
                Text(file.formattedSize)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                selectedFile?.id == file.id
                ? Color.cyan.opacity(0.08)
                : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - File Detail Panel
    
    private func fileDetailPanel(_ file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            
            HStack {
                Image(systemName: file.typeIcon)
                    .foregroundStyle(categoryColor(file.fileType))
                Text(file.filename)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        explorerFile = file
                        showFileExplorer = true
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)
                    .help("Open in File Explorer")
                    
                    Button {
                        withAnimation { selectedFile = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Metadata grid
            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 4) {
                metaItem("Size", value: file.formattedSize)
                
                if let duration = file.formattedDuration {
                    metaItem("Duration", value: duration)
                }
                if let res = file.resolution {
                    metaItem("Resolution", value: res)
                }
                if let fps = file.frameRate {
                    metaItem("Frame Rate", value: fps == floor(fps) ? "\(Int(fps)) fps" : String(format: "%.2f fps", fps))
                }
                if let codec = file.codec {
                    metaItem("Codec", value: codec)
                }
                if let cs = file.colorSpace {
                    metaItem("Color Space", value: cs)
                }
                if let model = file.cameraModel {
                    metaItem("Camera", value: model)
                }
                if let lens = file.lens {
                    metaItem("Lens", value: lens)
                }
                if let iso = file.iso {
                    metaItem("ISO", value: "\(iso)")
                }
                if let shutter = file.shutterSpeed {
                    metaItem("Shutter", value: shutter)
                }
                if let sr = file.sampleRate {
                    metaItem("Sample Rate", value: "\(Int(sr)) Hz")
                }
                if let ch = file.channels {
                    metaItem("Channels", value: ch == 1 ? "Mono" : ch == 2 ? "Stereo" : "\(ch)")
                }
                if let ac = file.audioCodec {
                    metaItem("Audio Codec", value: ac)
                }
            }
            
            // Visual tags
            if !file.visualTags.isEmpty {
                FlowLayoutCompact(spacing: 3) {
                    ForEach(file.visualTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.1), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }
            }
            
            // AI Description (from Ollama)
            if !file.visualDescription.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 8))
                            .foregroundStyle(.cyan)
                        Text("AI Description")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.cyan)
                    }
                    Text(file.visualDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            
            // Detected text (OCR)
            if !file.detectedText.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                        Text("Detected Text")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    Text(file.detectedText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            
            // Face count
            if file.faceCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 9))
                        .foregroundStyle(.pink)
                    Text("\(file.faceCount) face\(file.faceCount == 1 ? "" : "s") detected")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            
            // GPS coordinates
            if let lat = file.gpsLatitude, let lon = file.gpsLongitude {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 9))
                        .foregroundStyle(.teal)
                    Text(String(format: "%.4f, %.4f", lat, lon))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            // File path
            Text(file.relativePath)
                .font(.system(size: 9))
                .foregroundStyle(.gray.opacity(0.4))
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Helpers
    
    private func metaItem(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
    }
    
    private func categoryIcon(_ type: MediaFileType) -> String {
        switch type {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .projectFile: return "doc.badge.gearshape"
        case .other: return "doc"
        }
    }
    
    private func categoryColor(_ type: MediaFileType) -> Color {
        switch type {
        case .video: return .blue
        case .audio: return .green
        case .image: return .purple
        case .projectFile: return .orange
        case .other: return .gray
        }
    }
}
