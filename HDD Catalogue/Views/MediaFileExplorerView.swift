import SwiftUI
import AVKit
import CoreImage

/// Full-screen file explorer with video playback, S-Log3 LUT overlay,
/// image preview, and comprehensive metadata inspector.
struct MediaFileExplorerView: View {
    let project: Project
    let initialFile: MediaFile?
    @Binding var isPresented: Bool
    
    @State private var selectedFile: MediaFile?
    @State private var expandedCategories: Set<String> = ["Video", "Image"]
    @State private var player: AVPlayer?
    @State private var isLUTEnabled = true
    @State private var previewImage: NSImage?
    
    private var groupedFiles: [(category: MediaFileType, files: [MediaFile])] {
        let groups = Dictionary(grouping: project.mediaFiles) { $0.fileType }
        return MediaFileType.allCases.compactMap { type in
            guard let files = groups[type], !files.isEmpty else { return nil }
            return (category: type, files: files.sorted { $0.filename < $1.filename })
        }
    }
    
    var body: some View {
        HSplitView {
            // Left: File sidebar
            fileSidebar
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 340)
            
            // Right: Preview + Metadata
            VStack(spacing: 0) {
                if let file = selectedFile {
                    // Preview area
                    previewArea(file)
                    
                    Divider()
                    
                    // Metadata inspector
                    metadataInspector(file)
                } else {
                    emptyState
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(.background)
        .onAppear {
            selectedFile = initialFile ?? project.mediaFiles.first
            if let file = selectedFile {
                loadPreview(for: file)
            }
        }
        .onChange(of: selectedFile?.id) { _, _ in
            if let file = selectedFile {
                loadPreview(for: file)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    // MARK: - File Sidebar
    
    private var fileSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("\(project.mediaFiles.count) files")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
            
            Divider()
            
            // File tree
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(groupedFiles, id: \.category) { group in
                        sidebarCategory(group.category, files: group.files)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    @ViewBuilder
    private func sidebarCategory(_ category: MediaFileType, files: [MediaFile]) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.25)) {
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
                        .background(Color.gray.opacity(0.15), in: Capsule())
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if expandedCategories.contains(category.rawValue) {
                ForEach(files, id: \.id) { file in
                    sidebarFileRow(file)
                }
            }
        }
    }
    
    private func sidebarFileRow(_ file: MediaFile) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedFile = file
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: file.typeIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(categoryColor(file.fileType))
                    .frame(width: 14)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.filename)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if !file.metadataBadge.isEmpty {
                        Text(file.metadataBadge)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.cyan)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if let dur = file.formattedDuration {
                    Text(dur)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                
                Text(file.formattedSize)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .padding(.leading, 12)
            .background(
                selectedFile?.id == file.id
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Preview Area
    
    @ViewBuilder
    private func previewArea(_ file: MediaFile) -> some View {
        switch file.fileType {
        case .video:
            videoPreview(file)
        case .image:
            imagePreview(file)
        case .audio:
            audioPreview(file)
        default:
            genericPreview(file)
        }
    }
    
    private func videoPreview(_ file: MediaFile) -> some View {
        VStack(spacing: 0) {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            } else {
                loadingView("Loading video…")
            }
            
            // LUT toggle bar
            if isLogFootage(file) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    
                    Text("S-Log3 → Rec. 709")
                        .font(.system(size: 11, weight: .medium))
                    
                    Toggle("", isOn: $isLUTEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: isLUTEnabled) { _, _ in
                            if let file = selectedFile {
                                loadPreview(for: file)
                            }
                        }
                    
                    Spacer()
                    
                    Text("Non-destructive preview only")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
    }
    
    private func imagePreview(_ file: MediaFile) -> some View {
        Group {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            } else {
                loadingView("Loading image…")
            }
        }
    }
    
    private func audioPreview(_ file: MediaFile) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing)
                )
            
            Text(file.filename)
                .font(.headline)
            
            if let dur = file.formattedDuration {
                Text(dur)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 44)
                    .frame(maxWidth: 400)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.3))
    }
    
    private func genericPreview(_ file: MediaFile) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: file.typeIcon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(file.filename)
                .font(.headline)
            Text(file.formattedSize)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func loadingView(_ text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a file to preview")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Metadata Inspector
    
    private func metadataInspector(_ file: MediaFile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // File header
                HStack(spacing: 8) {
                    Image(systemName: file.typeIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(categoryColor(file.fileType))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.filename)
                            .font(.system(size: 13, weight: .semibold))
                        Text(file.relativePath)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    
                    Spacer()
                    
                    // Reveal in Finder
                    if project.drive?.isConnected == true {
                        Button {
                            let path = project.folderPath + "/" + file.relativePath
                            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: project.folderPath)
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Reveal in Finder")
                    }
                }
                
                Divider()
                
                // Metadata grid
                metadataGrid(file)
                
                // Visual tags
                if !file.visualTags.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionLabel("Visual Tags", icon: "tag.fill", color: .purple)
                        FlowLayoutCompact(spacing: 4) {
                            ForEach(file.visualTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.purple.opacity(0.1), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                }
                
                // AI Description
                if !file.visualDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionLabel("AI Description", icon: "brain", color: .cyan)
                        Text(file.visualDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                
                // Detected text
                if !file.detectedText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionLabel("Detected Text (OCR)", icon: "doc.text.viewfinder", color: .orange)
                        Text(file.detectedText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(5)
                    }
                }
                
                // Faces & GPS
                HStack(spacing: 16) {
                    if file.faceCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.rectangle")
                                .font(.system(size: 10))
                                .foregroundStyle(.pink)
                            Text("\(file.faceCount) face\(file.faceCount == 1 ? "" : "s")")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let lat = file.gpsLatitude, let lon = file.gpsLongitude {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10))
                                .foregroundStyle(.teal)
                            Text(String(format: "%.4f, %.4f", lat, lon))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(height: 220)
    }
    
    // MARK: - Metadata Grid
    
    private func metadataGrid(_ file: MediaFile) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 8) {
            // Universal
            metaCell("Size", file.formattedSize, icon: "doc", color: .gray)
            
            if let dur = file.formattedDuration {
                metaCell("Duration", dur, icon: "clock", color: .blue)
            }
            
            if let dm = file.dateModified {
                metaCell("Modified", dm.formatted(date: .abbreviated, time: .shortened), icon: "calendar", color: .gray)
            }
            
            // Video-specific
            if let res = file.resolution {
                metaCell("Resolution", res, icon: "rectangle.split.3x3", color: .blue)
            }
            if let fps = file.frameRate {
                let fpsStr = fps == floor(fps) ? "\(Int(fps)) fps" : String(format: "%.2f fps", fps)
                metaCell("Frame Rate", fpsStr, icon: "speedometer", color: .orange)
            }
            if let codec = file.codec {
                metaCell("Codec", codec, icon: "cpu", color: .purple)
            }
            if let cs = file.colorSpace {
                let isLog = cs.lowercased().contains("log") || cs.lowercased().contains("s-gamut")
                metaCell("Color Space", cs, icon: "paintpalette", color: isLog ? .orange : .green)
            }
            if let br = file.bitrate {
                let mbps = Double(br) / 1_000_000
                metaCell("Bitrate", String(format: "%.0f Mbps", mbps), icon: "waveform.path", color: .cyan)
            }
            
            // Image-specific
            if let cam = file.cameraModel {
                metaCell("Camera", cam, icon: "camera", color: .indigo)
            }
            if let lens = file.lens {
                metaCell("Lens", lens, icon: "camera.aperture", color: .indigo)
            }
            if let iso = file.iso {
                metaCell("ISO", "\(iso)", icon: "sun.max", color: .yellow)
            }
            if let shutter = file.shutterSpeed {
                metaCell("Shutter", shutter, icon: "timer", color: .orange)
            }
            if file.fileType == .image, let w = file.imageWidth, let h = file.imageHeight {
                metaCell("Dimensions", "\(w) × \(h)", icon: "rectangle.split.3x3", color: .blue)
            }
            
            // Audio-specific
            if let sr = file.sampleRate {
                metaCell("Sample Rate", "\(Int(sr)) Hz", icon: "waveform", color: .green)
            }
            if let ch = file.channels {
                let chStr = ch == 1 ? "Mono" : ch == 2 ? "Stereo" : "\(ch) channels"
                metaCell("Channels", chStr, icon: "speaker.wave.2", color: .green)
            }
            if let ac = file.audioCodec {
                metaCell("Audio Codec", ac, icon: "waveform.badge.magnifyingglass", color: .green)
            }
        }
    }
    
    private func metaCell(_ label: String, _ value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(color.opacity(0.7))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
    
    private func sectionLabel(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        }
    }
    
    // MARK: - Preview Loading
    
    private func loadPreview(for file: MediaFile) {
        player?.pause()
        player = nil
        previewImage = nil
        
        guard project.drive?.isConnected == true else { return }
        let filePath = project.folderPath + "/" + file.relativePath
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else { return }
        
        switch file.fileType {
        case .video:
            loadVideoPlayer(url: fileURL, file: file)
        case .audio:
            // Simple audio playback via AVPlayer
            player = AVPlayer(url: fileURL)
        case .image:
            loadImage(url: fileURL)
        default:
            break
        }
    }
    
    private func loadVideoPlayer(url: URL, file: MediaFile) {
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Apply S-Log3 → Rec. 709 LUT if applicable
        if isLogFootage(file) && isLUTEnabled {
            if let composition = createSLog3ToRec709Composition(for: asset) {
                playerItem.videoComposition = composition
            }
        }
        
        player = AVPlayer(playerItem: playerItem)
        player?.play()
    }
    
    private func loadImage(url: URL) {
        Task {
            let image = NSImage(contentsOf: url)
            await MainActor.run {
                previewImage = image
            }
        }
    }
    
    // MARK: - S-Log3 → Rec. 709 LUT
    
    /// Check if a file is LOG footage that needs a LUT.
    private func isLogFootage(_ file: MediaFile) -> Bool {
        guard let cs = file.colorSpace?.lowercased() else { return false }
        return cs.contains("log") || cs.contains("s-gamut") || cs.contains("v-log") ||
               cs.contains("c-log") || cs.contains("n-log") || cs.contains("hlg")
    }
    
    /// Creates an AVVideoComposition that applies a basic S-Log3 → Rec. 709
    /// tone curve using CIFilters. Non-destructive, preview only.
    private func createSLog3ToRec709Composition(for asset: AVAsset) -> AVVideoComposition? {
        // Use CIFilter-based video composition for the tone curve
        let composition = AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage.clampedToExtent()
            
            // Step 1: Apply a tone curve that maps S-Log3 to roughly Rec. 709.
            // S-Log3 has lifted blacks (~10% at 0 IRE) and compressed highlights.
            // This curve restores contrast and saturation.
            guard let toneCurve = CIFilter(name: "CIToneCurve") else {
                request.finish(with: source, context: nil)
                return
            }
            
            toneCurve.setValue(source, forKey: kCIInputImageKey)
            // Map S-Log3 curve: lift shadows, increase midtone contrast, gentle highlight rolloff
            toneCurve.setValue(CIVector(x: 0.0, y: 0.0), forKey: "inputPoint0")      // Blacks → crush
            toneCurve.setValue(CIVector(x: 0.10, y: 0.0), forKey: "inputPoint1")     // Lift → true black
            toneCurve.setValue(CIVector(x: 0.42, y: 0.50), forKey: "inputPoint2")     // Midtones → boost
            toneCurve.setValue(CIVector(x: 0.70, y: 0.85), forKey: "inputPoint3")     // Upper mids → S-curve
            toneCurve.setValue(CIVector(x: 1.0, y: 1.0), forKey: "inputPoint4")       // Highlights → peak
            
            guard let curved = toneCurve.outputImage else {
                request.finish(with: source, context: nil)
                return
            }
            
            // Step 2: Boost saturation (S-Log3 is desaturated)
            guard let vibrance = CIFilter(name: "CIVibrance") else {
                request.finish(with: curved.cropped(to: request.sourceImage.extent), context: nil)
                return
            }
            vibrance.setValue(curved, forKey: kCIInputImageKey)
            vibrance.setValue(0.5, forKey: "inputAmount")  // Gentle saturation boost
            
            guard let final = vibrance.outputImage else {
                request.finish(with: curved.cropped(to: request.sourceImage.extent), context: nil)
                return
            }
            
            request.finish(with: final.cropped(to: request.sourceImage.extent), context: nil)
        }
        
        return composition
    }
    
    // MARK: - Helpers
    
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
