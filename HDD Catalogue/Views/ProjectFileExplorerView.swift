import SwiftUI
import AVFoundation
import AVKit
import ImageIO
import CoreMedia

// MARK: - FileSystemItem Model

/// Represents a file or folder from the actual filesystem.
struct FileSystemItem: Identifiable, Hashable {
    let id: String            // Absolute path
    let name: String
    let absolutePath: String
    let relativePath: String  // Relative to project root
    let isDirectory: Bool
    let fileSize: Int64
    let dateModified: Date?
    let fileExtension: String
    
    /// Associated MediaFile from the deep index (if available)
    var mediaFile: MediaFile?
    
    var isVideo: Bool {
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "mxf", "m4v", "wmv", "flv", "webm", "mpg", "mpeg", "m2ts", "ts", "r3d", "braw", "ari"]
        return videoExts.contains(fileExtension.lowercased())
    }
    
    var isImage: Bool {
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "pef", "gif", "bmp", "webp", "svg", "psd", "psb"]
        return imageExts.contains(fileExtension.lowercased())
    }
    
    var isAudio: Bool {
        let audioExts: Set<String> = ["mp3", "wav", "aac", "flac", "m4a", "aiff", "aif", "ogg", "wma", "alac"]
        return audioExts.contains(fileExtension.lowercased())
    }
    
    var isProjectFile: Bool {
        let projExts: Set<String> = ["prproj", "fcpxd", "drp", "aep", "sesx", "motn"]
        return projExts.contains(fileExtension.lowercased())
    }
    
    var typeIcon: String {
        if isDirectory { return "folder.fill" }
        if isVideo { return "film" }
        if isImage { return "photo" }
        if isAudio { return "waveform" }
        if isProjectFile { return "doc.badge.gearshape" }
        return "doc"
    }
    
    var typeColor: Color {
        if isDirectory { return .orange }
        if isVideo { return .blue }
        if isImage { return .purple }
        if isAudio { return .green }
        if isProjectFile { return .orange }
        return .gray
    }
    
    var formattedSize: String {
        if isDirectory { return "" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var metadataBadge: String {
        mediaFile?.metadataBadge ?? ""
    }
    
    var formattedDuration: String? {
        mediaFile?.formattedDuration
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - LiveMetadata (extracted directly from files)

/// Metadata extracted live from video/image/audio files using AVAsset and CGImageSource.
struct LiveMetadata {
    // Video
    var resolution: String?
    var videoCodec: String?
    var frameRate: Double?
    var durationSeconds: Double?
    var formattedDuration: String?
    var bitrate: Int64?
    var colorSpace: String?
    var colorPrimaries: String?
    var transferFunction: String?
    var pixelDepth: String?
    
    // Audio (track in video, or standalone audio file)
    var audioCodec: String?
    var sampleRate: Double?
    var audioChannels: Int?
    
    // Image
    var imageWidth: Int?
    var imageHeight: Int?
    var colorProfile: String?
    var cameraModel: String?
    var cameraMake: String?
    var lensModel: String?
    var focalLength: Double?
    var aperture: Double?
    var isoValue: Int?
    var shutterSpeed: String?
    var whiteBalance: String?
    
    // Camera inference (from folder-level detection)
    var inferredCamera: String?
    var inferredLens: String?
    var inferredGamma: String?
    var inferredColorGamut: String?
    var inferredCodecDetail: String?
    var inferenceSource: String?
}

// MARK: - Folder Camera Profile (cached per folder)

/// Camera profile detected once per folder and applied to all files within.
struct FolderCameraProfile {
    var camera: String?
    var lens: String?
    var gamma: String?
    var gamut: String?
    var codecDetail: String?
    var source: String        // "XML Sidecar", "Folder Name", "AI Detection", "File Pattern"
    var isDetecting: Bool = false
}

// MARK: - ProjectFileExplorerView

/// Full file explorer that replaces the grid when a user double-clicks a project card.
/// Three-pane layout: folder tree (left) · file grid with hover scrubbing (center) · detail panel (right).
struct ProjectFileExplorerView: View {
    let project: Project
    @Binding var isPresented: Project?
    var initialFilePath: String? = nil  // Relative path to navigate to on open
    @Binding var searchText: String
    
    @State private var currentPath: String = ""          // Relative path from project root
    @State private var selectedItem: FileSystemItem?
    @State private var detailItem: FileSystemItem?       // File shown in detail panel (double-click)
    @State private var expandedFolders: Set<String> = []
    @State private var viewMode: FileViewMode = .grid
    @State private var player: AVPlayer?
    @State private var previewImage: NSImage?
    @State private var liveMetadata: LiveMetadata?
    @State private var folderCameraCache: [String: FolderCameraProfile] = [:]  // Camera profile per folder
    @State private var detectingFolders: Set<String> = []                      // Folders currently being detected
    @State private var lutEnabled: Bool = false                                // LUT color conversion toggle
    @State private var currentLUTFilter: CIFilter?                             // Active LUT filter
    @State private var directoryContents: [String: [FileSystemItem]] = [:] // Cache per path
    @State private var folderTreeItems: [FileSystemItem] = []              // All folders
    
    enum FileViewMode: String {
        case grid, list
    }
    
    private var projectRoot: String { project.folderPath }
    private var isConnected: Bool { project.drive?.isConnected == true }
    
    /// Build a lookup of relative path → MediaFile for enrichment
    private var mediaFileLookup: [String: MediaFile] {
        var lookup: [String: MediaFile] = [:]
        for mf in project.mediaFiles {
            lookup[mf.relativePath] = mf
        }
        return lookup
    }
    
    /// Current directory items (files + subfolders)
    private var currentItems: [FileSystemItem] {
        let items = directoryContents[currentPath] ?? []
        if searchText.isEmpty { return items }
        // When searching, return recursive results instead
        return []
    }
    
    /// Subfolders in current directory (hidden during search)
    private var currentSubfolders: [FileSystemItem] {
        if !searchText.isEmpty { return [] }
        return currentItems.filter(\.isDirectory).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    
    /// Files (non-folders) in current directory — recursive when searching
    private var currentFiles: [FileSystemItem] {
        if !searchText.isEmpty {
            return recursiveSearchResults
        }
        return currentItems.filter { !$0.isDirectory }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    
    /// Recursively find all files matching searchText under the current path
    private var recursiveSearchResults: [FileSystemItem] {
        guard !searchText.isEmpty, isConnected else { return [] }
        // Always search from project root for unified search
        let rootURL = URL(fileURLWithPath: projectRoot)
        let lookup = mediaFileLookup
        
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        var results: [FileSystemItem] = []
        
        for case let itemURL as URL in enumerator {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = resourceValues?.isDirectory ?? false
            if isDir { continue } // Only show files in search results
            
            let name = itemURL.lastPathComponent
            
            // Build relative path from project root
            let fullPath = itemURL.path
            let relPath = fullPath.hasPrefix(projectRoot + "/")
                ? String(fullPath.dropFirst(projectRoot.count + 1))
                : itemURL.lastPathComponent
            
            // Check filename + MediaFile metadata for match
            let mf = lookup[relPath]
            let query = searchText.lowercased()
            let matchesName = name.localizedCaseInsensitiveContains(searchText)
            let matchesMedia = mf.map { file in
                (file.codec ?? "").lowercased().contains(query) ||
                (file.cameraModel ?? "").lowercased().contains(query) ||
                (file.colorSpace ?? "").lowercased().contains(query) ||
                (file.resolution ?? "").lowercased().contains(query) ||
                file.metadataBadge.lowercased().contains(query) ||
                file.visualTags.contains(where: { $0.lowercased().contains(query) }) ||
                file.visualDescription.lowercased().contains(query) ||
                file.fileExtension.lowercased().contains(query)
            } ?? false
            
            guard matchesName || matchesMedia else { continue }
            
            let item = FileSystemItem(
                id: fullPath,
                name: name,
                absolutePath: fullPath,
                relativePath: relPath,
                isDirectory: false,
                fileSize: Int64(resourceValues?.fileSize ?? 0),
                dateModified: resourceValues?.contentModificationDate,
                fileExtension: itemURL.pathExtension,
                mediaFile: mf
            )
            results.append(item)
            
            if results.count >= 200 { break } // Cap results
        }
        
        return results.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    
    private var breadcrumbs: [String] {
        if currentPath.isEmpty { return [] }
        return currentPath.split(separator: "/").map(String.init)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            explorerHeader
            
            Divider()
            
            // Three-pane body
            HSplitView {
                // Left: Folder tree
                folderSidebar
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                
                // Center: File grid/list
                fileContentArea
                    .frame(minWidth: 400)
                
                // Right: Detail panel (slides in when a file is double-clicked)
                if let item = detailItem {
                    fileDetailPanel(item)
                        .frame(minWidth: 300, idealWidth: 360, maxWidth: 440)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(Color(red: 0.09, green: 0.09, blue: 0.12))
        .onAppear {
            currentPath = ""
            scanDirectory(at: "")
            scanAllFolders()
            
            // Navigate to initial file if provided (from search)
            if let filePath = initialFilePath {
                let components = filePath.split(separator: "/").map(String.init)
                if components.count > 1 {
                    // Navigate to the parent folder
                    let parentPath = components.dropLast().joined(separator: "/")
                    currentPath = parentPath
                    scanDirectory(at: parentPath)
                    
                    // Expand all ancestor folders in the sidebar
                    var accumulated = ""
                    for component in components.dropLast() {
                        accumulated = accumulated.isEmpty ? component : accumulated + "/" + component
                        expandedFolders.insert(accumulated)
                    }
                }
                
                // Select the file after a short delay to let directory scan complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let fullPath = projectRoot + "/" + filePath
                    if FileManager.default.fileExists(atPath: fullPath) {
                        let url = URL(fileURLWithPath: fullPath)
                        let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath)
                        let item = FileSystemItem(
                            id: fullPath,
                            name: url.lastPathComponent,
                            absolutePath: fullPath,
                            relativePath: filePath,
                            isDirectory: false,
                            fileSize: attrs?[.size] as? Int64 ?? 0,
                            dateModified: attrs?[.modificationDate] as? Date,
                            fileExtension: url.pathExtension.lowercased()
                        )
                        selectedItem = item
                        detailItem = item
                    }
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    // MARK: - Filesystem Scanning
    
    /// Scan a directory and cache results
    private func scanDirectory(at relativePath: String) {
        guard isConnected else { return }
        let fullPath = relativePath.isEmpty ? projectRoot : projectRoot + "/" + relativePath
        let url = URL(fileURLWithPath: fullPath)
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        let lookup = mediaFileLookup
        var items: [FileSystemItem] = []
        
        for itemURL in contents {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = resourceValues?.isDirectory ?? false
            let size = Int64(resourceValues?.fileSize ?? 0)
            let modified = resourceValues?.contentModificationDate
            let relPath = relativePath.isEmpty ? itemURL.lastPathComponent : relativePath + "/" + itemURL.lastPathComponent
            
            var item = FileSystemItem(
                id: itemURL.path,
                name: itemURL.lastPathComponent,
                absolutePath: itemURL.path,
                relativePath: relPath,
                isDirectory: isDir,
                fileSize: size,
                dateModified: modified,
                fileExtension: itemURL.pathExtension,
                mediaFile: lookup[relPath]
            )
            _ = item // Suppress warning
            items.append(item)
        }
        
        directoryContents[relativePath] = items
    }
    
    /// Scan all folders recursively for the sidebar tree
    private func scanAllFolders() {
        guard isConnected else { return }
        var folders: [FileSystemItem] = []
        
        func scanRecursive(_ relativePath: String) {
            let fullPath = relativePath.isEmpty ? projectRoot : projectRoot + "/" + relativePath
            let url = URL(fileURLWithPath: fullPath)
            
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            
            for itemURL in contents {
                let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    let relPath = relativePath.isEmpty ? itemURL.lastPathComponent : relativePath + "/" + itemURL.lastPathComponent
                    let item = FileSystemItem(
                        id: itemURL.path,
                        name: itemURL.lastPathComponent,
                        absolutePath: itemURL.path,
                        relativePath: relPath,
                        isDirectory: true,
                        fileSize: 0,
                        dateModified: nil,
                        fileExtension: "",
                        mediaFile: nil
                    )
                    folders.append(item)
                    scanRecursive(relPath)
                }
            }
        }
        
        scanRecursive("")
        folderTreeItems = folders
    }
    
    // MARK: - Folder Tree Helpers
    
    /// Build a FolderNode tree from the scanned folder items
    private var folderTree: [FolderNode] {
        FolderNode.buildTreeFromPaths(folderTreeItems.map(\.relativePath))
    }
    
    /// Flattened list of folder nodes for the sidebar
    private var flatFolderList: [(node: FolderNode, level: Int)] {
        var result: [(node: FolderNode, level: Int)] = []
        func flatten(_ nodes: [FolderNode], level: Int) {
            for node in nodes {
                result.append((node, level))
                if expandedFolders.contains(node.path) {
                    flatten(node.children, level: level + 1)
                }
            }
        }
        flatten(folderTree, level: 1)
        return result
    }
    
    /// Count of files in a folder (from cached directory contents)
    private func fileCount(in path: String) -> Int {
        if let cached = directoryContents[path] {
            return cached.filter { !$0.isDirectory }.count
        }
        return 0
    }
    
    // MARK: - Header
    
    private var explorerHeader: some View {
        HStack(spacing: 12) {
            // Back button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isPresented = nil
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            
            // Separator
            Rectangle().fill(.quaternary).frame(width: 1, height: 20)
            
            // Project icon + name
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
            Text(project.displayName)
                .font(.system(size: 13, weight: .semibold))
            
            // Breadcrumbs
            if !breadcrumbs.isEmpty {
                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { idx, crumb in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                    
                    Button {
                        let path = breadcrumbs[0...idx].joined(separator: "/")
                        navigateTo(path)
                    } label: {
                        Text(crumb)
                            .font(.system(size: 12, weight: idx == breadcrumbs.count - 1 ? .semibold : .regular))
                            .foregroundStyle(idx == breadcrumbs.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            

            
            // View toggle
            Picker("", selection: $viewMode) {
                Image(systemName: "square.grid.2x2")
                    .tag(FileViewMode.grid)
                Image(systemName: "list.bullet")
                    .tag(FileViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            
            // File count
            Text("\(currentFiles.count + currentSubfolders.count) items")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
    
    // MARK: - Navigation
    
    private func navigateTo(_ path: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            currentPath = path
        }
        if directoryContents[path] == nil {
            scanDirectory(at: path)
        }
    }
    
    // MARK: - Folder Sidebar
    
    private var folderSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Folders")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Root
                    folderRow(name: project.displayName, path: "", level: 0)
                    
                    // Flattened folder tree
                    ForEach(flatFolderList, id: \.node.path) { item in
                        folderRow(name: item.node.name, path: item.node.path, level: item.level)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.13))
    }
    
    private func folderRow(name: String, path: String, level: Int) -> some View {
        let isSelected = currentPath == path
        let children = folderTree(for: path)
        let hasChildren = !children.isEmpty
        
        return Button {
            navigateTo(path)
            if hasChildren {
                if expandedFolders.contains(path) {
                    expandedFolders.remove(path)
                } else {
                    expandedFolders.insert(path)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if hasChildren {
                    Image(systemName: expandedFolders.contains(path) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }
                
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .blue : .orange.opacity(0.7))
                
                Text(name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .padding(.leading, CGFloat(level) * 14)
            .background(
                isSelected
                ? Color.blue.opacity(0.12)
                : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func folderTree(for path: String) -> [FolderNode] {
        if path.isEmpty {
            return folderTree
        }
        func find(in nodes: [FolderNode]) -> [FolderNode] {
            for node in nodes {
                if node.path == path { return node.children }
                let result = find(in: node.children)
                if !result.isEmpty { return result }
            }
            return []
        }
        return find(in: folderTree)
    }
    
    // MARK: - File Content Area
    
    private var fileContentArea: some View {
        ScrollView {
            switch viewMode {
            case .grid:
                fileGridView
            case .list:
                fileListView
            }
        }
        .background(Color(red: 0.09, green: 0.09, blue: 0.12))
    }
    
    private var fileGridView: some View {
        let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)]
        
        return LazyVGrid(columns: columns, spacing: 14) {
            // Subfolders first
            ForEach(currentSubfolders) { folder in
                FolderGridTile(name: folder.name) {
                    navigateTo(folder.relativePath)
                    expandedFolders.insert(folder.relativePath)
                }
            }
            
            // Files
            ForEach(currentFiles) { file in
                FSFileGridTile(
                    item: file,
                    isSelected: selectedItem?.id == file.id
                ) {
                    selectedItem = file
                } onDoubleClick: {
                    openDetailPanel(for: file)
                }
            }
        }
        .padding(16)
    }
    
    private var fileListView: some View {
        LazyVStack(spacing: 1) {
            // Subfolders
            ForEach(currentSubfolders) { folder in
                fileListFolderRow(folder)
            }
            
            // Files
            ForEach(currentFiles) { file in
                fileListFileRow(file)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func fileListFolderRow(_ folder: FileSystemItem) -> some View {
        Button {
            navigateTo(folder.relativePath)
            expandedFolders.insert(folder.relativePath)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                    .frame(width: 24)
                
                Text(folder.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func fileListFileRow(_ item: FileSystemItem) -> some View {
        let isSelected = selectedItem?.id == item.id
        
        return HStack(spacing: 10) {
            Image(systemName: item.typeIcon)
                .font(.system(size: 12))
                .foregroundStyle(item.typeColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                
                if !item.metadataBadge.isEmpty {
                    Text(item.metadataBadge)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.cyan)
                }
            }
            
            Spacer()
            
            if let dur = item.formattedDuration {
                Text(dur)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            Text(item.formattedSize)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.blue.opacity(0.12) : Color.white.opacity(0.02),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openDetailPanel(for: item)
        }
        .onTapGesture {
            selectedItem = item
        }
    }
    
    // MARK: - Detail Panel
    
    private func openDetailPanel(for item: FileSystemItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            detailItem = item
            liveMetadata = nil
        }
        loadPreview(for: item)
        extractLiveMetadata(for: item)
    }
    
    @ViewBuilder
    private func fileDetailPanel(_ item: FileSystemItem) -> some View {
        VStack(spacing: 0) {
            // Detail header
            HStack {
                Image(systemName: item.typeIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(item.typeColor)
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        player?.pause()
                        player = nil
                        previewImage = nil
                        detailItem = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Preview area
                    previewArea(item)
                        .frame(minHeight: 200, maxHeight: 320)
                    
                    Divider()
                    
                    // Metadata
                    VStack(alignment: .leading, spacing: 14) {
                        // File info
                        VStack(alignment: .leading, spacing: 6) {
                            detailSectionLabel("File Info", icon: "doc.text", color: .blue)
                            
                            metaRow("Name", value: item.name)
                            metaRow("Path", value: item.relativePath)
                            metaRow("Size", value: item.formattedSize)
                            if let dm = item.dateModified {
                                metaRow("Modified", value: dm.formatted(date: .abbreviated, time: .shortened))
                            }
                            metaRow("Extension", value: item.fileExtension.uppercased())
                        }
                        
                        // Video metadata — live extracted + MediaFile fallback
                        if item.isVideo {
                            VStack(alignment: .leading, spacing: 6) {
                                detailSectionLabel("Video", icon: "film", color: .blue)
                                
                                let mf = item.mediaFile
                                let lm = liveMetadata
                                
                                if let res = lm?.resolution ?? mf?.resolution {
                                    metaRow("Resolution", value: res)
                                }
                                if let codec = lm?.videoCodec ?? mf?.codec {
                                    metaRow("Codec", value: codec)
                                }
                                if let fps = lm?.frameRate ?? mf?.frameRate {
                                    let fpsStr = fps == floor(fps) ? "\(Int(fps)) fps" : String(format: "%.2f fps", fps)
                                    metaRow("Frame Rate", value: fpsStr)
                                }
                                if let dur = lm?.formattedDuration ?? mf?.formattedDuration {
                                    metaRow("Duration", value: dur)
                                }
                                if let br = lm?.bitrate ?? mf?.bitrate {
                                    let mbps = Double(br) / 1_000_000
                                    metaRow("Bitrate", value: String(format: "%.1f Mbps", mbps))
                                }
                                if let cs = lm?.colorSpace ?? mf?.colorSpace {
                                    metaRow("Color Space", value: cs)
                                }
                                if let cp = lm?.colorPrimaries {
                                    metaRow("Primaries", value: cp)
                                }
                                if let tf = lm?.transferFunction {
                                    metaRow("Transfer", value: tf)
                                }
                                if let pd = lm?.pixelDepth {
                                    metaRow("Bit Depth", value: pd)
                                }
                            }
                            
                            // Camera inference section
                            if let lm = liveMetadata, lm.inferredCamera != nil || lm.inferredGamma != nil {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 4) {
                                        detailSectionLabel("Camera", icon: "camera.fill", color: .orange)
                                        Spacer()
                                        if let src = lm.inferenceSource {
                                            Text(src)
                                                .font(.system(size: 8, weight: .medium))
                                                .foregroundStyle(.tertiary)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(.quaternary, in: Capsule())
                                        }
                                    }
                                    
                                    if let cam = lm.inferredCamera {
                                        metaRow("Camera", value: cam)
                                    }
                                    if let lens = lm.inferredLens {
                                        metaRow("Lens", value: lens)
                                    }
                                    if let gamma = lm.inferredGamma {
                                        metaRow("Log/Gamma", value: gamma)
                                    }
                                    if let gamut = lm.inferredColorGamut {
                                        metaRow("Color Gamut", value: gamut)
                                    }
                                    if let cd = lm.inferredCodecDetail {
                                        metaRow("Codec Detail", value: cd)
                                    }
                                }
                            }
                            
                            // Audio track info
                            if let lm = liveMetadata, lm.audioCodec != nil || lm.sampleRate != nil {
                                VStack(alignment: .leading, spacing: 6) {
                                    detailSectionLabel("Audio Track", icon: "waveform", color: .green)
                                    
                                    if let ac = lm.audioCodec {
                                        metaRow("Codec", value: ac)
                                    }
                                    if let sr = lm.sampleRate {
                                        metaRow("Sample Rate", value: "\(Int(sr)) Hz")
                                    }
                                    if let ch = lm.audioChannels {
                                        metaRow("Channels", value: ch == 1 ? "Mono" : ch == 2 ? "Stereo" : "\(ch) ch")
                                    }
                                }
                            }
                        }
                        
                        // Image metadata — live extracted + MediaFile fallback
                        if item.isImage {
                            VStack(alignment: .leading, spacing: 6) {
                                detailSectionLabel("Image", icon: "photo", color: .purple)
                                
                                let mf = item.mediaFile
                                let lm = liveMetadata
                                
                                if let w = lm?.imageWidth ?? mf?.imageWidth, let h = lm?.imageHeight ?? mf?.imageHeight {
                                    metaRow("Dimensions", value: "\(w) × \(h)")
                                }
                                if let cp = lm?.colorProfile {
                                    metaRow("Color Profile", value: cp)
                                }
                                if let bd = lm?.pixelDepth {
                                    metaRow("Bit Depth", value: bd)
                                }
                                if let cam = lm?.cameraModel ?? mf?.cameraModel {
                                    metaRow("Camera", value: cam)
                                }
                                if let make = lm?.cameraMake {
                                    metaRow("Make", value: make)
                                }
                                if let lens = lm?.lensModel ?? mf?.lens {
                                    metaRow("Lens", value: lens)
                                }
                                if let fl = lm?.focalLength {
                                    metaRow("Focal Length", value: String(format: "%.0f mm", fl))
                                }
                                if let ap = lm?.aperture {
                                    metaRow("Aperture", value: String(format: "ƒ/%.1f", ap))
                                }
                                if let iso = lm?.isoValue ?? mf?.iso {
                                    metaRow("ISO", value: "\(iso)")
                                }
                                if let shutter = lm?.shutterSpeed ?? mf?.shutterSpeed {
                                    metaRow("Shutter", value: shutter)
                                }
                                if let wb = lm?.whiteBalance {
                                    metaRow("White Balance", value: wb)
                                }
                            }
                        }
                        
                        // Audio file metadata
                        if item.isAudio {
                            VStack(alignment: .leading, spacing: 6) {
                                detailSectionLabel("Audio", icon: "waveform", color: .green)
                                
                                let mf = item.mediaFile
                                let lm = liveMetadata
                                
                                if let dur = lm?.formattedDuration {
                                    metaRow("Duration", value: dur)
                                }
                                if let sr = lm?.sampleRate ?? mf?.sampleRate {
                                    metaRow("Sample Rate", value: "\(Int(sr)) Hz")
                                }
                                if let ch = lm?.audioChannels ?? mf?.channels {
                                    metaRow("Channels", value: ch == 1 ? "Mono" : ch == 2 ? "Stereo" : "\(ch) channels")
                                }
                                if let ac = lm?.audioCodec ?? mf?.audioCodec {
                                    metaRow("Codec", value: ac)
                                }
                                if let br = lm?.bitrate {
                                    metaRow("Bitrate", value: "\(br / 1000) kbps")
                                }
                            }
                        }
                        
                        // Visual tags
                        if let mf = item.mediaFile, !mf.visualTags.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                detailSectionLabel("Visual Tags", icon: "tag.fill", color: .purple)
                                FlowLayoutCompact(spacing: 4) {
                                    ForEach(mf.visualTags, id: \.self) { tag in
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
                        if let mf = item.mediaFile, !mf.visualDescription.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                detailSectionLabel("AI Description", icon: "brain", color: .cyan)
                                Text(mf.visualDescription)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        
                        // GPS
                        if let mf = item.mediaFile, let lat = mf.gpsLatitude, let lon = mf.gpsLongitude {
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
                        
                        // Actions
                        Button {
                            NSWorkspace.shared.selectFile(item.absolutePath, inFileViewerRootedAtPath: projectRoot)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                }
            }
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.13))
        .overlay(alignment: .leading) {
            Rectangle().fill(.quaternary).frame(width: 0.5)
        }
    }
    
    // MARK: - Preview
    
    @ViewBuilder
    private func previewArea(_ item: FileSystemItem) -> some View {
        if item.isVideo {
            if let player {
                ZStack(alignment: .topTrailing) {
                    VideoPlayer(player: player)
                        .background(.black)
                    
                    // LUT toggle button
                    Button {
                        lutEnabled.toggle()
                        reapplyLUT(for: item)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: lutEnabled ? "camera.filters" : "camera")
                                .font(.system(size: 11, weight: .semibold))
                            Text(lutEnabled ? "Rec.709" : "LOG")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(lutEnabled ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            lutEnabled
                            ? Color.orange.opacity(0.85)
                            : Color.black.opacity(0.5),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            } else {
                previewPlaceholder("Loading video…", icon: "film")
            }
        } else if item.isImage {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(.black)
            } else {
                previewPlaceholder("Loading image…", icon: "photo")
            }
        } else if item.isAudio {
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                if let dur = item.formattedDuration {
                    Text(dur)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 44)
                        .frame(maxWidth: 300)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.black.opacity(0.3))
        } else {
            previewPlaceholder(item.name, icon: item.typeIcon)
        }
    }
    
    private func previewPlaceholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(.black.opacity(0.2))
    }
    
    private func loadPreview(for item: FileSystemItem) {
        player?.pause()
        player = nil
        previewImage = nil
        currentLUTFilter = nil
        
        guard isConnected else { return }
        let fileURL = URL(fileURLWithPath: item.absolutePath)
        guard FileManager.default.fileExists(atPath: item.absolutePath) else { return }
        
        if item.isVideo {
            let asset = AVAsset(url: fileURL)
            let playerItem = AVPlayerItem(asset: asset)
            
            // Apply LUT if enabled
            if lutEnabled {
                if let lutFilter = loadLUTForItem(item) {
                    currentLUTFilter = lutFilter
                    applyLUTToPlayerItem(playerItem, filter: lutFilter)
                }
            }
            
            let p = AVPlayer(playerItem: playerItem)
            player = p
            p.play()
        } else if item.isAudio {
            player = AVPlayer(url: fileURL)
        } else if item.isImage {
            Task {
                let image = NSImage(contentsOf: fileURL)
                await MainActor.run { previewImage = image }
            }
        }
    }
    
    // MARK: - LUT Color Conversion
    
    /// Re-apply or remove LUT when toggle is pressed
    private func reapplyLUT(for item: FileSystemItem) {
        guard let currentPlayer = player else { return }
        let currentTime = currentPlayer.currentTime()
        let wasPlaying = currentPlayer.rate > 0
        
        currentPlayer.pause()
        player = nil
        
        let fileURL = URL(fileURLWithPath: item.absolutePath)
        let asset = AVAsset(url: fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        
        if lutEnabled {
            if let lutFilter = loadLUTForItem(item) {
                currentLUTFilter = lutFilter
                applyLUTToPlayerItem(playerItem, filter: lutFilter)
            }
        } else {
            currentLUTFilter = nil
        }
        
        let p = AVPlayer(playerItem: playerItem)
        player = p
        p.seek(to: currentTime)
        if wasPlaying { p.play() }
    }
    
    /// Select the correct LUT file based on the inferred camera/gamma
    private func loadLUTForItem(_ item: FileSystemItem) -> CIFilter? {
        let folderPath = (item.relativePath as NSString).deletingLastPathComponent
        let profile = folderCameraCache[folderPath]
        let gamma = profile?.gamma?.lowercased() ?? liveMetadata?.inferredGamma?.lowercased() ?? ""
        let camera = profile?.camera?.lowercased() ?? liveMetadata?.inferredCamera?.lowercased() ?? ""
        
        let basePath = "/Users/timonterzic/Documents/Presets/LUTs"
        
        // Map gamma/camera to specific LUT file
        var lutPath: String?
        
        if gamma.contains("s-log 3") || gamma.contains("s-log3") || gamma.contains("slog3") {
            lutPath = basePath + "/REC709LUT/Sony Slog3-S-Gamut3.Cine_To_s709.cube"
        } else if gamma.contains("s-log 2") || gamma.contains("slog2") {
            lutPath = basePath + "/REC709LUT/Sony From_SLog2SGumut_To_LC-709_.cube"
        } else if gamma.contains("d-log m") || gamma.contains("dlog m") {
            if camera.contains("mavic 4") {
                lutPath = basePath + "/DJI/DJI Mavic 4 Pro D-Log M to Rec.709 V1.cube"
            } else if camera.contains("osmo pocket") {
                lutPath = basePath + "/DJI/DJI OSMO Pocket 3 D-Log M to Rec.709 V1.cube"
            } else if camera.contains("osmo action") || camera.contains("action 4") {
                lutPath = basePath + "/DJI/DJI OSMO Action 4 D-Log M to Rec.709 V1.cube"
            } else {
                // Default DJI D-Log M
                lutPath = basePath + "/DJI/DJI Mavic 4 Pro D-Log M to Rec.709 V1.cube"
            }
        } else if gamma.contains("d-log") || gamma.contains("dlog") {
            lutPath = basePath + "/DJI/DJI Mavic 3 D-Log to Rec.709 V1.cube"
        } else if gamma.contains("canon log") || gamma.contains("clog") {
            lutPath = basePath + "/REC709LUT/Canon CxxxLog10toRec709_Full.cube"
        } else if gamma.contains("v-log") || gamma.contains("vlog") {
            lutPath = basePath + "/REC709LUT/Panasonic VLogL to Like709.cube"
        } else if gamma.contains("n-log") || gamma.contains("nlog") {
            lutPath = basePath + "/REC709LUT/Nikon Z_6_N-Log-Full_to_REC709-Full_33_V01-00.cube"
        } else if gamma.contains("f-log") || gamma.contains("flog") {
            lutPath = basePath + "/REC709LUT/FUJIFILM XT3_FLog_FGamut_to_FLog_BT.709_33grid_V.1.00.cube"
        } else if gamma.contains("braw") || gamma.contains("blackmagic") {
            lutPath = basePath + "/REC709LUT/BMD  Rec709.cube"
        } else if camera.contains("gopro") {
            // GoPro doesn't usually need a LUT, but provide generic Sony as fallback
            return nil
        }
        
        // Fallback: try Sony S-Log 3 as a general Log-to-709
        if lutPath == nil {
            lutPath = basePath + "/REC709LUT/Sony Slog3-S-Gamut3.Cine_To_s709.cube"
        }
        
        guard let path = lutPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return loadCIFilterFromCube(at: path)
    }
    
    /// Apply a CIFilter LUT to an AVPlayerItem via AVVideoComposition
    private func applyLUTToPlayerItem(_ playerItem: AVPlayerItem, filter: CIFilter) {
        let composition = AVVideoComposition(asset: playerItem.asset, applyingCIFiltersWithHandler: { request in
            let source = request.sourceImage.clampedToExtent()
            filter.setValue(source, forKey: kCIInputImageKey)
            
            if let output = filter.outputImage?.cropped(to: request.sourceImage.extent) {
                request.finish(with: output, context: nil)
            } else {
                request.finish(with: request.sourceImage, context: nil)
            }
        })
        playerItem.videoComposition = composition
    }
    
    /// Load a .cube LUT file and create a CIColorCubeWithColorSpace filter
    private func loadCIFilterFromCube(at path: String) -> CIFilter? {
        guard let (size, data) = parseCubeFile(at: path) else { return nil }
        
        let filter = CIFilter(name: "CIColorCubeWithColorSpace")
        filter?.setValue(size, forKey: "inputCubeDimension")
        filter?.setValue(data, forKey: "inputCubeData")
        filter?.setValue(CGColorSpace(name: CGColorSpace.sRGB), forKey: "inputColorSpace")
        
        return filter
    }
    
    /// Parse a standard .cube 3D LUT file into (size, float data)
    private func parseCubeFile(at path: String) -> (Int, Data)? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        
        var size = 0
        var values: [Float] = []
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("TITLE") { continue }
            
            // Parse LUT size (handles both spaces and tabs as separators)
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(whereSeparator: \.isWhitespace)
                if parts.count >= 2, let s = Int(parts[1]) {
                    size = s
                }
                continue
            }
            
            // Skip other metadata
            if trimmed.hasPrefix("DOMAIN_MIN") || trimmed.hasPrefix("DOMAIN_MAX") || trimmed.hasPrefix("LUT_") { continue }
            
            // Parse RGB values (handles spaces and tabs)
            let parts = trimmed.split(whereSeparator: \.isWhitespace)
            if parts.count >= 3,
               let r = Float(parts[0]),
               let g = Float(parts[1]),
               let b = Float(parts[2]) {
                values.append(r)
                values.append(g)
                values.append(b)
                values.append(1.0) // Alpha
            }
        }
        
        guard size > 0, values.count == size * size * size * 4 else { return nil }
        
        let data = values.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        return (size, data)
    }
    
    // MARK: - Live Metadata Extraction
    
    private func extractLiveMetadata(for item: FileSystemItem) {
        guard isConnected else { return }
        let fileURL = URL(fileURLWithPath: item.absolutePath)
        guard FileManager.default.fileExists(atPath: item.absolutePath) else { return }
        
        Task {
            var meta = LiveMetadata()
            
            if item.isVideo || item.isAudio {
                let asset = AVAsset(url: fileURL)
                
                // Duration
                if let duration = try? await asset.load(.duration) {
                    let seconds = CMTimeGetSeconds(duration)
                    if seconds > 0 && !seconds.isNaN {
                        meta.durationSeconds = seconds
                        let mins = Int(seconds) / 60
                        let secs = Int(seconds) % 60
                        if seconds >= 3600 {
                            let hrs = Int(seconds) / 3600
                            meta.formattedDuration = String(format: "%d:%02d:%02d", hrs, mins % 60, secs)
                        } else {
                            meta.formattedDuration = String(format: "%d:%02d", mins, secs)
                        }
                    }
                }
                
                // Estimated bitrate (file size / duration)
                if let dur = meta.durationSeconds, dur > 0 {
                    let estimatedBitrate = Int64(Double(item.fileSize) * 8.0 / dur)
                    meta.bitrate = estimatedBitrate
                }
                
                // Video tracks
                if let videoTracks = try? await asset.loadTracks(withMediaType: .video), let videoTrack = videoTracks.first {
                    // Resolution
                    if let naturalSize = try? await videoTrack.load(.naturalSize) {
                        let w = Int(naturalSize.width)
                        let h = Int(naturalSize.height)
                        meta.resolution = "\(w) × \(h)"
                        meta.imageWidth = w
                        meta.imageHeight = h
                    }
                    
                    // Frame rate
                    if let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate), nominalFrameRate > 0 {
                        meta.frameRate = Double(nominalFrameRate)
                    }
                    
                    // Codec and color info from format descriptions
                    if let formatDescriptions = try? await videoTrack.load(.formatDescriptions), let fmtDesc = formatDescriptions.first {
                        let mediaSubType = CMFormatDescriptionGetMediaSubType(fmtDesc)
                        meta.videoCodec = fourCCToString(mediaSubType)
                        
                        // Bit depth from pixel format
                        let videoDimensions = CMVideoFormatDescriptionGetDimensions(fmtDesc)
                        _ = videoDimensions // used above for resolution
                        
                        // Extract pixel format to determine actual bit depth
                        if let extensions = CMFormatDescriptionGetExtensions(fmtDesc) as? [String: Any] {
                            if let matrix = extensions["CVImageBufferYCbCrMatrix"] as? String {
                                meta.colorSpace = cleanColorSpaceName(matrix)
                            }
                            if let primaries = extensions["CVImageBufferColorPrimaries"] as? String {
                                meta.colorPrimaries = cleanColorSpaceName(primaries)
                            }
                            if let transfer = extensions["CVImageBufferTransferFunction"] as? String {
                                meta.transferFunction = cleanColorSpaceName(transfer)
                            }
                            
                            // Bit depth: read BitsPerComponent if available (per-channel)
                            if let bpc = extensions["BitsPerComponent"] as? Int, bpc <= 16 {
                                meta.pixelDepth = "\(bpc)-bit"
                            }
                        }
                        
                        // Determine bit depth from the codec/pixel format if not already set
                        if meta.pixelDepth == nil {
                            meta.pixelDepth = bitDepthFromCodec(mediaSubType)
                        }
                    }
                }
                
                // Audio tracks
                if let audioTracks = try? await asset.loadTracks(withMediaType: .audio), let audioTrack = audioTracks.first {
                    if let formatDescriptions = try? await audioTrack.load(.formatDescriptions), let fmtDesc = formatDescriptions.first {
                        let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc)
                        if let basic = basicDesc?.pointee {
                            meta.sampleRate = basic.mSampleRate
                            meta.audioChannels = Int(basic.mChannelsPerFrame)
                        }
                        
                        let subType = CMFormatDescriptionGetMediaSubType(fmtDesc)
                        meta.audioCodec = fourCCToString(subType)
                    }
                }
                
            } else if item.isImage {
                // Use CGImageSource for image metadata
                guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                    await MainActor.run { liveMetadata = meta }
                    return
                }
                
                guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
                    await MainActor.run { liveMetadata = meta }
                    return
                }
                
                // Pixel dimensions
                if let w = properties[kCGImagePropertyPixelWidth as String] as? Int {
                    meta.imageWidth = w
                }
                if let h = properties[kCGImagePropertyPixelHeight as String] as? Int {
                    meta.imageHeight = h
                }
                
                // Bit depth
                if let depth = properties[kCGImagePropertyDepth as String] as? Int {
                    meta.pixelDepth = "\(depth)-bit"
                }
                
                // Color profile
                if let profileName = properties[kCGImagePropertyProfileName as String] as? String {
                    meta.colorProfile = profileName
                }
                
                // EXIF data
                if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                    // ISO
                    if let isoValues = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let iso = isoValues.first {
                        meta.isoValue = iso
                    }
                    
                    // Shutter speed (exposure time)
                    if let exposure = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                        if exposure >= 1 {
                            meta.shutterSpeed = String(format: "%.1f s", exposure)
                        } else {
                            let denominator = Int(round(1.0 / exposure))
                            meta.shutterSpeed = "1/\(denominator) s"
                        }
                    }
                    
                    // Aperture (F-number)
                    if let fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double {
                        meta.aperture = fNumber
                    }
                    
                    // Focal length
                    if let fl = exif[kCGImagePropertyExifFocalLength as String] as? Double {
                        meta.focalLength = fl
                    }
                    
                    // Lens model
                    if let lens = exif[kCGImagePropertyExifLensModel as String] as? String {
                        meta.lensModel = lens
                    }
                    
                    // White balance
                    if let wb = exif[kCGImagePropertyExifWhiteBalance as String] as? Int {
                        meta.whiteBalance = wb == 0 ? "Auto" : "Manual"
                    }
                }
                
                // TIFF data (camera make/model)
                if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                    if let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
                        meta.cameraModel = model
                    }
                    if let make = tiff[kCGImagePropertyTIFFMake as String] as? String {
                        meta.cameraMake = make
                    }
                }
            }
            
            // --- Camera / Color Space Inference (folder-level) ---
            if item.isVideo || item.isAudio {
                let folderPath = (item.relativePath as NSString).deletingLastPathComponent
                
                // Check folder cache first
                if let cached = await MainActor.run(body: { folderCameraCache[folderPath] }) {
                    meta.inferredCamera = cached.camera
                    meta.inferredLens = cached.lens
                    meta.inferredGamma = cached.gamma
                    meta.inferredColorGamut = cached.gamut
                    meta.inferredCodecDetail = cached.codecDetail
                    meta.inferenceSource = cached.source
                    // Use XML codec detail to correct bit depth (H422 = 10-bit)
                    if meta.pixelDepth == nil, let cd = cached.codecDetail {
                        meta.pixelDepth = bitDepthFromXMLCodec(cd)
                    }
                } else {
                    // Trigger folder-level detection (runs once per folder)
                    let isAlreadyDetecting = await MainActor.run(body: { detectingFolders.contains(folderPath) })
                    if !isAlreadyDetecting {
                        await MainActor.run { detectingFolders.insert(folderPath) }
                        let profile = await detectFolderCamera(folderPath: folderPath, sampleItem: item, sampleMeta: meta)
                        await MainActor.run {
                            folderCameraCache[folderPath] = profile
                            detectingFolders.remove(folderPath)
                        }
                        meta.inferredCamera = profile.camera
                        meta.inferredLens = profile.lens
                        meta.inferredGamma = profile.gamma
                        meta.inferredColorGamut = profile.gamut
                        meta.inferredCodecDetail = profile.codecDetail
                        meta.inferenceSource = profile.source
                        // Use XML codec detail to correct bit depth
                        if meta.pixelDepth == nil, let cd = profile.codecDetail {
                            meta.pixelDepth = bitDepthFromXMLCodec(cd)
                        }
                    }
                }
            }
            
            await MainActor.run {
                liveMetadata = meta
            }
        }
    }
    /// Determine bit depth from the video codec FourCC
    private func bitDepthFromCodec(_ code: FourCharCode) -> String? {
        // Known 10-bit codecs
        let tenBit: Set<FourCharCode> = [
            0x68766331, // hvc1 - HEVC (typically 10-bit)
            0x68657631, // hev1 - HEVC
            0x61706368, // apch - ProRes 422 HQ (10-bit)
            0x6170636E, // apcn - ProRes 422 (10-bit)
            0x61706373, // apcs - ProRes 422 LT (10-bit)
            0x6170636F, // apco - ProRes 422 Proxy (10-bit)
        ]
        // Known 12-bit codecs
        let twelveBit: Set<FourCharCode> = [
            0x61703468, // ap4h - ProRes 4444 (12-bit)
            0x61703478, // ap4x - ProRes 4444 XQ (12-bit)
        ]
        
        if twelveBit.contains(code) { return "12-bit" }
        if tenBit.contains(code) { return "10-bit" }
        // H.264 can be 8-bit or 10-bit depending on profile, don't assume
        return nil
    }
    
    /// Determine bit depth from Sony XML codec detail string (e.g. "AVC200_3840_2160_H422P@L52")
    private func bitDepthFromXMLCodec(_ codecDetail: String) -> String? {
        let upper = codecDetail.uppercased()
        // H422P = High 4:2:2 Profile = 10-bit (Sony XAVC S 4:2:2)
        if upper.contains("H422") { return "10-bit" }
        // XAVC HS (HEVC based) = typically 10-bit
        if upper.contains("XAVCHS") || upper.contains("XAVC_HS") { return "10-bit" }
        // XAVC S-I with 4:2:2 = 10-bit
        if upper.contains("422") { return "10-bit" }
        // Standard H.264 High Profile = 8-bit
        if upper.contains("H264") || upper.contains("AVC") {
            // If it has H42x it's been caught above; remaining is likely 8-bit 4:2:0
            return "8-bit"
        }
        return nil
    }
    
    /// Convert a FourCC code (like 'avc1') to a human-readable string
    private func fourCCToString(_ code: FourCharCode) -> String {
        let knownCodecs: [FourCharCode: String] = [
            0x61766331: "H.264 (AVC)",     // 'avc1'
            0x68766331: "H.265 (HEVC)",    // 'hvc1'
            0x68657631: "H.265 (HEVC)",    // 'hev1'
            0x61703468: "ProRes 4444",      // 'ap4h'
            0x61706368: "ProRes 422 HQ",   // 'apch'
            0x6170636E: "ProRes 422",      // 'apcn'
            0x61706373: "ProRes 422 LT",   // 'apcs'
            0x6170636F: "ProRes 422 Proxy", // 'apco'
            0x61703478: "ProRes 4444 XQ",  // 'ap4x'
            0x6D703461: "AAC",             // 'mp4a'
            0x61616320: "AAC",             // 'aac '
            0x616C6163: "ALAC",            // 'alac'
            0x6C70636D: "LPCM",            // 'lpcm'
            0x2E6D7033: "MP3",             // '.mp3'
        ]
        
        if let name = knownCodecs[code] {
            return name
        }
        
        // Fallback: convert FourCC to string
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        let str = String(bytes: bytes, encoding: .ascii) ?? "Unknown"
        return str.trimmingCharacters(in: .whitespaces)
    }
    
    /// Clean up AVFoundation color space string constants
    private func cleanColorSpaceName(_ raw: String) -> String {
        let mapping: [String: String] = [
            "ITU_R_709_2": "Rec. 709",
            "ITU_R_2020": "Rec. 2020",
            "SMPTE_ST_2084_PQ": "PQ (HDR10)",
            "ITU_R_2100_HLG": "HLG",
            "Linear": "Linear",
            "IEC_sRGB": "sRGB",
            "P3_D65": "Display P3",
        ]
        return mapping[raw] ?? raw
    }
    
    // MARK: - Folder-Level Camera Detection
    
    /// Detect camera profile for an entire folder by sampling one clip.
    /// Tries XML → folder name → file pattern → Qwen AI in that order.
    private func detectFolderCamera(folderPath: String, sampleItem: FileSystemItem, sampleMeta: LiveMetadata) async -> FolderCameraProfile {
        
        // Layer 1: Try XML sidecar on this sample clip
        let xmlMeta = parseSonyXMLSidecar(for: sampleItem)
        if let xml = xmlMeta, xml.camera != nil {
            return FolderCameraProfile(
                camera: xml.camera, lens: xml.lens, gamma: xml.gamma,
                gamut: xml.gamut, codecDetail: xml.codecDetail, source: "XML Sidecar"
            )
        }
        
        // Also try finding ANY XML sidecar in the folder
        let folderAbsPath = folderPath.isEmpty ? projectRoot : projectRoot + "/" + folderPath
        if let xmlFromFolder = findAnySonyXMLInFolder(folderAbsPath) {
            return FolderCameraProfile(
                camera: xmlFromFolder.camera, lens: xmlFromFolder.lens, gamma: xmlFromFolder.gamma,
                gamut: xmlFromFolder.gamut, codecDetail: xmlFromFolder.codecDetail, source: "XML Sidecar"
            )
        }
        
        // Layer 2: Folder name heuristics
        let folderInference = inferCameraFromFolderPath(sampleItem.relativePath)
        if let fi = folderInference {
            return FolderCameraProfile(
                camera: fi.camera, lens: nil, gamma: fi.gamma,
                gamut: fi.gamut, codecDetail: nil, source: "Folder Name"
            )
        }
        
        // Layer 3: File name pattern
        let fileInference = inferCameraFromFileName(sampleItem.name)
        if let fi = fileInference {
            // For file pattern, also try Qwen to get more detail
            let context = gatherFolderContext(folderAbsPath: folderAbsPath, folderRelPath: folderPath, sampleMeta: sampleMeta)
            if let aiResult = await callQwenForCameraDetection(context: context) {
                return FolderCameraProfile(
                    camera: aiResult.camera ?? fi.camera,
                    lens: aiResult.lens, 
                    gamma: aiResult.gamma ?? fi.gamma,
                    gamut: aiResult.gamut ?? fi.gamut,
                    codecDetail: nil, source: "AI Detection"
                )
            }
            return FolderCameraProfile(
                camera: fi.camera, lens: nil, gamma: fi.gamma,
                gamut: fi.gamut, codecDetail: nil, source: "File Pattern"
            )
        }
        
        // Layer 4: Qwen AI with full context
        let context = gatherFolderContext(folderAbsPath: folderAbsPath, folderRelPath: folderPath, sampleMeta: sampleMeta)
        if let aiResult = await callQwenForCameraDetection(context: context) {
            return FolderCameraProfile(
                camera: aiResult.camera, lens: aiResult.lens,
                gamma: aiResult.gamma, gamut: aiResult.gamut,
                codecDetail: nil, source: "AI Detection"
            )
        }
        
        // Fallback: unknown
        return FolderCameraProfile(camera: nil, lens: nil, gamma: nil, gamut: nil, codecDetail: nil, source: "Unknown")
    }
    
    /// Find any Sony XML sidecar in the folder
    private func findAnySonyXMLInFolder(_ folderAbsPath: String) -> SidecarMetadata? {
        let url = URL(fileURLWithPath: folderAbsPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        
        for fileURL in contents {
            if fileURL.pathExtension.uppercased() == "XML" {
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                let parser = SonyXMLSidecarParser()
                if let result = parser.parse(data: data), result.camera != nil {
                    return result
                }
            }
        }
        return nil
    }
    
    /// Gather context about a folder for the AI prompt
    private func gatherFolderContext(folderAbsPath: String, folderRelPath: String, sampleMeta: LiveMetadata) -> String {
        let folderName = (folderRelPath as NSString).lastPathComponent
        let parentPath = (folderRelPath as NSString).deletingLastPathComponent
        let parentFolder = parentPath.isEmpty ? project.displayName : (parentPath as NSString).lastPathComponent
        
        // List files in folder
        let url = URL(fileURLWithPath: folderAbsPath)
        let fileNames: [String]
        if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            fileNames = contents.map(\.lastPathComponent).sorted()
        } else {
            fileNames = []
        }
        
        let fileList = fileNames.prefix(15).joined(separator: ", ")
        let totalFiles = fileNames.count
        let videoFiles = fileNames.filter { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return ["mp4", "mov", "mxf", "avi", "mkv", "m4v"].contains(ext)
        }
        
        var context = """
        Project: \(project.displayName)
        Parent folder: \(parentFolder)
        Camera folder: \(folderName)
        Total files: \(totalFiles)
        Sample files: \(fileList)
        Video files count: \(videoFiles.count)
        """
        
        // Add sample clip metadata
        if let codec = sampleMeta.videoCodec {
            context += "\nVideo codec: \(codec)"
        }
        if let res = sampleMeta.resolution {
            context += "\nResolution: \(res)"
        }
        if let fps = sampleMeta.frameRate {
            context += "\nFrame rate: \(fps) fps"
        }
        if let cs = sampleMeta.colorSpace {
            context += "\nColor matrix: \(cs)"
        }
        if let cp = sampleMeta.colorPrimaries {
            context += "\nColor primaries: \(cp)"
        }
        if let tf = sampleMeta.transferFunction {
            context += "\nTransfer function: \(tf)"
        }
        if let ac = sampleMeta.audioCodec {
            context += "\nAudio codec: \(ac)"
        }
        if let depth = sampleMeta.pixelDepth {
            context += "\nBit depth: \(depth)"
        }
        
        return context
    }
    
    /// Call local Qwen AI to identify camera and color profile from folder context
    private func callQwenForCameraDetection(context: String) async -> (camera: String?, lens: String?, gamma: String?, gamut: String?)? {
        let prompt = """
        You are a video production expert. From the following folder and clip metadata, identify the camera model and color profile used.
        
        \(context)
        
        Common cameras and their naming:
        - Sony Alpha (A7IV, A7V, ZV-E1, FX3, FX6, FX30): files named C####.MP4, uses XAVC S/HS, LPCM audio, S-Log 3 / S-Cinetone
        - DJI drones (Mavic, Mini, Air, Inspire): files named DJI_####.MP4, uses H.264/HEVC, D-Log M / D-Log / Normal
        - GoPro: files named GX######.MP4 or GOPR####.MP4, uses HEVC, GoPro Color / GoPro Flat
        - Canon (R5, R6, C70): files named MVI_####.MP4, Canon Log 3
        - Blackmagic: files named A/B###.braw, Blackmagic Film
        
        If the folder name or parent folders hint at the camera (e.g. "Mavic", "ZV-E1", "A7IV", "FPV"), use that as strong evidence.
        Folder named "FPV" almost certainly means GoPro footage.
        DJI Mavic drones typically shoot in D-Log M color profile.
        Sony cameras in professional use typically shoot in S-Log 3 with S-Gamut3.Cine.
        
        Return ONLY a JSON object (no markdown, no explanation):
        {"camera": "Full camera name", "gamma": "Color profile/log", "gamut": "Color gamut or null", "confidence": 0.9}
        """
        
        let ollamaURL = URL(string: "http://localhost:11434/api/chat")!
        var request = URLRequest(url: ollamaURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        let modelName = UserDefaults.standard.string(forKey: "ollamaReasoningModel") ?? "qwen3.5:4b"
        
        let body: [String: Any] = [
            "model": modelName,
            "messages": [["role": "user", "content": prompt]],
            "stream": false,
            "think": false,
            "format": "json",
            "options": ["temperature": 0.1, "num_predict": 256]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            return nil
        }
        
        // Parse the JSON response
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown fences if present
        if cleaned.hasPrefix("```") {
            if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[start...end])
            }
        }
        
        guard let responseData = cleaned.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return nil
        }
        
        let camera = result["camera"] as? String
        let gamma = result["gamma"] as? String
        let gamut = result["gamut"] as? String
        
        // Only return if we got something meaningful
        guard camera != nil || gamma != nil else { return nil }
        
        return (camera: camera, lens: nil, gamma: gamma, gamut: gamut)
    }
    
    // MARK: - Camera Inference Helpers
    
    struct SidecarMetadata {
        var camera: String?
        var lens: String?
        var gamma: String?
        var gamut: String?
        var codecDetail: String?
    }
    
    /// Layer 1: Parse Sony XML sidecar files (C####M01.XML) for rich camera metadata
    private func parseSonyXMLSidecar(for item: FileSystemItem) -> SidecarMetadata? {
        let name = item.name
        // Sony naming: {prefix}####.MP4 → {prefix}####M01.XML (works with C####, TT####, etc.)
        let ext = (name as NSString).pathExtension.lowercased()
        guard ["mp4", "mov", "mxf"].contains(ext),
              let dotIndex = name.lastIndex(of: ".") else { return nil }
        
        let baseName = String(name[name.startIndex..<dotIndex])
        let dir = (item.absolutePath as NSString).deletingLastPathComponent
        
        // Try common sidecar patterns
        let sidecarNames = [
            "\(baseName)M01.XML",
            "\(baseName)M01.xml",
            "\(baseName).XML",
            "\(baseName).xml",
        ]
        
        var sidecarURL: URL?
        for sn in sidecarNames {
            let path = dir + "/" + sn
            if FileManager.default.fileExists(atPath: path) {
                sidecarURL = URL(fileURLWithPath: path)
                break
            }
        }
        
        guard let url = sidecarURL,
              let data = try? Data(contentsOf: url) else { return nil }
        
        let parser = SonyXMLSidecarParser()
        return parser.parse(data: data)
    }
    
    struct CameraInference {
        var camera: String
        var gamma: String?
        var gamut: String?
    }
    
    /// Layer 2: Infer camera from folder path components
    private func inferCameraFromFolderPath(_ relativePath: String) -> CameraInference? {
        let components = relativePath.split(separator: "/").map(String.init)
        // Check each folder component (skip the filename itself)
        let folders = components.count > 1 ? Array(components.dropLast()) : components
        
        for folder in folders {
            let lower = folder.lowercased()
                .trimmingCharacters(in: .whitespaces)
            
            // Sony cameras
            if lower.contains("a7iv") || lower.contains("a7m4") || lower.contains("a741") || lower.contains("a742") || lower.contains("a7 iv") {
                return CameraInference(camera: "Sony A7 IV (ILCE-7M4)", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower.contains("a7v") || lower.contains("a7m5") {
                return CameraInference(camera: "Sony A7V (ILCE-7M5)", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower.contains("a7siii") || lower.contains("a7s3") || lower.contains("a7sm3") {
                return CameraInference(camera: "Sony A7S III", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower.contains("a7iii") || lower.contains("a7m3") || lower.contains("a73") {
                return CameraInference(camera: "Sony A7 III", gamma: "S-Log 2/3", gamut: "S-Gamut3")
            }
            if lower.contains("a7c") {
                return CameraInference(camera: "Sony A7C", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower.contains("a7r") {
                return CameraInference(camera: "Sony A7R", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower.contains("zv-e1") || lower.contains("zve1") || lower.contains("zv e1") {
                return CameraInference(camera: "Sony ZV-E1", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower.contains("zv-e10") || lower.contains("zve10") {
                return CameraInference(camera: "Sony ZV-E10", gamma: "S-Log 2/3", gamut: "S-Gamut3")
            }
            if lower.contains("fx3") {
                return CameraInference(camera: "Sony FX3", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower.contains("fx6") {
                return CameraInference(camera: "Sony FX6", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower.contains("fx30") {
                return CameraInference(camera: "Sony FX30", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower.contains("fx9") {
                return CameraInference(camera: "Sony FX9", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            if lower == "sony c" || lower.contains("sony cinema") {
                return CameraInference(camera: "Sony Cinema Line", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
            }
            
            // DJI drones
            if lower.contains("mavic 4 pro") || lower.contains("mavic4pro") {
                return CameraInference(camera: "DJI Mavic 4 Pro", gamma: "D-Log M", gamut: nil)
            }
            if lower.contains("mavic 3") || lower.contains("mavic3") {
                return CameraInference(camera: "DJI Mavic 3", gamma: "D-Log", gamut: nil)
            }
            if lower.contains("mavic") {
                return CameraInference(camera: "DJI Mavic", gamma: "D-Log M", gamut: nil)
            }
            if lower.contains("mini 4 pro") || lower.contains("mini4pro") {
                return CameraInference(camera: "DJI Mini 4 Pro", gamma: "D-Log M", gamut: nil)
            }
            if lower.contains("mini") && lower.contains("dji") {
                return CameraInference(camera: "DJI Mini", gamma: "D-Log M", gamut: nil)
            }
            if lower.contains("air 3") || lower.contains("air3") {
                return CameraInference(camera: "DJI Air 3", gamma: "D-Log M", gamut: nil)
            }
            if lower.contains("inspire") {
                return CameraInference(camera: "DJI Inspire", gamma: "D-Log", gamut: nil)
            }
            
            // GoPro / FPV
            if lower == "fpv" || lower.contains("gopro") {
                return CameraInference(camera: "GoPro", gamma: "GoPro Color", gamut: nil)
            }
            
            // Canon
            if lower.contains("r5") || lower.contains("eos r5") {
                return CameraInference(camera: "Canon EOS R5", gamma: "Canon Log 3", gamut: "Cinema Gamut")
            }
            if lower.contains("r6") || lower.contains("eos r6") {
                return CameraInference(camera: "Canon EOS R6", gamma: "Canon Log 3", gamut: nil)
            }
            if lower.contains("c70") {
                return CameraInference(camera: "Canon C70", gamma: "Canon Log 3", gamut: "Cinema Gamut")
            }
            
            // Blackmagic
            if lower.contains("bmpcc") || lower.contains("blackmagic") || lower.contains("pocket") {
                return CameraInference(camera: "Blackmagic Pocket", gamma: "BRAW / Film", gamut: "Blackmagic Wide Gamut")
            }
            
            // RED
            if lower.contains("red") && (lower.contains("komodo") || lower.contains("dsmc")) {
                return CameraInference(camera: "RED", gamma: "REDLogFilm", gamut: "REDWideGamutRGB")
            }
        }
        
        return nil
    }
    
    /// Layer 3: Infer camera brand from file name patterns
    private func inferCameraFromFileName(_ fileName: String) -> CameraInference? {
        let upper = fileName.uppercased()
        
        // Sony: C####.MP4
        if upper.range(of: #"^C\d{4,5}\."#, options: .regularExpression) != nil {
            return CameraInference(camera: "Sony Alpha/Cinema", gamma: "S-Log 3", gamut: "S-Gamut3.Cine")
        }
        
        // GoPro: GX######.MP4, GOPR####.MP4, GP######.MP4
        if upper.range(of: #"^(GX|GOPR|GP)\d{4,8}\."#, options: .regularExpression) != nil {
            return CameraInference(camera: "GoPro", gamma: "GoPro Color", gamut: nil)
        }
        
        // DJI: DJI_####.MP4
        if upper.range(of: #"^DJI_\d{4,8}\."#, options: .regularExpression) != nil {
            return CameraInference(camera: "DJI", gamma: "D-Log M", gamut: nil)
        }
        
        // Canon: MVI_####.MP4, IMG_####.MP4 (could also be iPhone)
        if upper.range(of: #"^MVI_\d{4}\."#, options: .regularExpression) != nil {
            return CameraInference(camera: "Canon", gamma: nil, gamut: nil)
        }
        
        // Blackmagic: A###.braw, B###.braw
        if upper.range(of: #"^[AB]\d{3,4}\.BRAW$"#, options: .regularExpression) != nil {
            return CameraInference(camera: "Blackmagic", gamma: "BRAW / Film", gamut: "Blackmagic Wide Gamut")
        }
        
        return nil
    }
    
    // MARK: - Detail Helpers
    
    private func detailSectionLabel(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        }
    }
    
    private func metaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Sony XML Sidecar Parser

/// Parses Sony NonRealTimeMeta XML sidecar files to extract camera, lens, and color metadata.
class SonyXMLSidecarParser: NSObject, XMLParserDelegate {
    private var result = ProjectFileExplorerView.SidecarMetadata()
    private var currentElement = ""
    private var currentAttributes: [String: String] = [:]
    private var insideCameraUnitMetadata = false
    
    func parse(data: Data) -> ProjectFileExplorerView.SidecarMetadata? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        
        // Only return if we found something useful
        if result.camera != nil || result.gamma != nil || result.lens != nil {
            return result
        }
        return nil
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentAttributes = attributeDict
        
        switch elementName {
        case "Device":
            let make = attributeDict["manufacturer"] ?? ""
            let model = attributeDict["modelName"] ?? ""
            if !model.isEmpty {
                let displayModel = sonyModelToDisplayName(model)
                result.camera = make.isEmpty ? displayModel : "\(make) \(displayModel)"
            }
            
        case "Lens":
            if let lens = attributeDict["modelName"], !lens.isEmpty {
                result.lens = lens
            }
            
        case "VideoFrame":
            if let codec = attributeDict["videoCodec"], !codec.isEmpty {
                result.codecDetail = codec
            }
            
        case "Group":
            if attributeDict["name"] == "CameraUnitMetadataSet" {
                insideCameraUnitMetadata = true
            }
            
        case "Item":
            if insideCameraUnitMetadata {
                let name = attributeDict["name"] ?? ""
                let value = attributeDict["value"] ?? ""
                
                switch name {
                case "CaptureGammaEquation":
                    result.gamma = cleanGammaName(value)
                case "CaptureColorPrimaries":
                    result.gamut = cleanGamutName(value)
                default:
                    break
                }
            }
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "Group" {
            insideCameraUnitMetadata = false
        }
    }
    
    /// Map Sony internal model names to display names
    private func sonyModelToDisplayName(_ model: String) -> String {
        let mapping: [String: String] = [
            "ILCE-7M4": "A7 IV",
            "ILCE-7M5": "A7V",
            "ILCE-7SM3": "A7S III",
            "ILCE-7M3": "A7 III",
            "ILCE-7RM5": "A7R V",
            "ILCE-7RM4": "A7R IV",
            "ILCE-7CR": "A7CR",
            "ILCE-7C": "A7C",
            "ILCE-7CM2": "A7C II",
            "ZV-E1": "ZV-E1",
            "ZV-E10": "ZV-E10",
            "ZV-E10M2": "ZV-E10 II",
            "ILME-FX3": "FX3",
            "ILME-FX6": "FX6",
            "ILME-FX30": "FX30",
            "MPC-2610": "FX9",
        ]
        return mapping[model] ?? model
    }
    
    private func cleanGammaName(_ raw: String) -> String {
        let mapping: [String: String] = [
            "s-log3-cine": "S-Log 3 Cine",
            "s-log3": "S-Log 3",
            "s-log2": "S-Log 2",
            "s-cinetone": "S-Cinetone",
            "cine-ei": "Cine EI",
            "rec709": "Rec. 709",
            "hlg": "HLG",
            "hlg1": "HLG 1",
            "hlg2": "HLG 2",
            "hlg3": "HLG 3",
        ]
        return mapping[raw.lowercased()] ?? raw
    }
    
    private func cleanGamutName(_ raw: String) -> String {
        let mapping: [String: String] = [
            "s-gamut3-cine": "S-Gamut3.Cine",
            "s-gamut3": "S-Gamut3",
            "s-gamut": "S-Gamut",
            "rec709": "Rec. 709",
            "rec2020": "Rec. 2020",
        ]
        return mapping[raw.lowercased()] ?? raw
    }
}

// MARK: - Folder Node Model

struct FolderNode: Identifiable {
    let name: String
    let path: String
    var children: [FolderNode]
    
    var id: String { path }
    
    /// Build tree from a list of relative folder paths
    static func buildTreeFromPaths(_ paths: [String]) -> [FolderNode] {
        var rootNodes: [FolderNode] = []
        var nodeMap: [String: Int] = [:] // path → index tracking
        
        let sortedPaths = paths.sorted()
        
        // First pass: create all root-level nodes
        for path in sortedPaths {
            let components = path.split(separator: "/").map(String.init)
            if components.count == 1 {
                rootNodes.append(FolderNode(name: components[0], path: path, children: []))
            }
        }
        
        // Second pass: add children
        for path in sortedPaths where path.contains("/") {
            let components = path.split(separator: "/").map(String.init)
            let parentPath = components.dropLast().joined(separator: "/")
            let name = components.last!
            let node = FolderNode(name: name, path: path, children: [])
            addChild(node, to: parentPath, in: &rootNodes)
        }
        
        return rootNodes
    }
    
    private static func addChild(_ child: FolderNode, to parentPath: String, in nodes: inout [FolderNode]) {
        for i in nodes.indices {
            if nodes[i].path == parentPath {
                nodes[i].children.append(child)
                return
            }
            addChild(child, to: parentPath, in: &nodes[i].children)
        }
    }
}

// MARK: - Folder Grid Tile

struct FolderGridTile: View {
    let name: String
    let onDoubleClick: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.15), Color.orange.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Image(systemName: "folder.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
            }
            .frame(height: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovering ? Color.orange.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
            )
            
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - File Grid Tile with Hover Scrubbing (Filesystem-based)

struct FSFileGridTile: View {
    let item: FileSystemItem
    let isSelected: Bool
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    
    @State private var isHovering = false
    @State private var scrubImage: NSImage?
    @State private var staticThumbnail: NSImage?
    @State private var hoverProgress: CGFloat = 0
    @State private var scrubTask: Task<Void, Never>?
    @State private var thumbnailTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail area
            ZStack {
                if let img = scrubImage ?? staticThumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 100)
                        .clipped()
                } else {
                    // Placeholder
                    ZStack {
                        Color(red: 0.12, green: 0.12, blue: 0.15)
                        Image(systemName: item.typeIcon)
                            .font(.system(size: 24))
                            .foregroundStyle(item.typeColor.opacity(0.4))
                    }
                    .frame(height: 100)
                }
                
                // Hover scrub progress indicator
                if isHovering && item.isVideo {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: geo.size.width * hoverProgress, height: 3)
                        }
                        .frame(height: 3)
                    }
                }
                
                // Duration badge for videos
                if let dur = item.formattedDuration {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(dur)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                                .padding(6)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            // File info below thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 6) {
                    if !item.metadataBadge.isEmpty {
                        Text(item.metadataBadge)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.cyan)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(item.formattedSize)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .background(
            isSelected
            ? Color.blue.opacity(0.12)
            : Color(red: 0.12, green: 0.14, blue: 0.18),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.blue.opacity(0.4) :
                    isHovering ? Color.white.opacity(0.12) : Color.white.opacity(0.04),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onTapGesture {
            onClick()
        }
        .onHover { hovering in
            isHovering = hovering
            if !hovering {
                scrubImage = nil
                hoverProgress = 0
                scrubTask?.cancel()
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard item.isVideo else { return }
                let estimatedWidth: CGFloat = 180
                let progress = max(0, min(1, location.x / estimatedWidth))
                hoverProgress = progress
                
                scrubTask?.cancel()
                scrubTask = Task {
                    await scrubFrame(at: progress)
                }
                
            case .ended:
                scrubImage = nil
                hoverProgress = 0
            @unknown default:
                break
            }
        }
        .onAppear {
            guard staticThumbnail == nil else { return }
            thumbnailTask = Task {
                await ThumbnailQueue.shared.enqueue {
                    await loadStaticThumbnail()
                }
            }
        }
        .onDisappear {
            thumbnailTask?.cancel()
        }
    }
    
    private func loadStaticThumbnail() async {
        let fileURL = URL(fileURLWithPath: item.absolutePath)
        guard FileManager.default.fileExists(atPath: item.absolutePath) else { return }
        
        if item.isVideo {
            let asset = AVAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 180, height: 180)
            
            let time = CMTime(seconds: 1, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run { staticThumbnail = img }
            }
        } else if item.isImage {
            // Use CGImageSource for fast, small thumbnail — doesn't decode the full RAW
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return }
            
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceShouldCacheImmediately: false
            ]
            
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
            let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            await MainActor.run { staticThumbnail = img }
        }
    }
    
    private func scrubFrame(at progress: CGFloat) async {
        let fileURL = URL(fileURLWithPath: item.absolutePath)
        let asset = AVAsset(url: fileURL)
        
        guard let duration = try? await asset.load(.duration) else { return }
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return }
        
        let targetTime = CMTime(seconds: totalSeconds * Double(progress), preferredTimescale: 600)
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        
        if let cgImage = try? await generator.image(at: targetTime).image {
            guard !Task.isCancelled else { return }
            let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            await MainActor.run {
                scrubImage = img
            }
        }
    }
}

// MARK: - Thumbnail Queue (sequential loading)

/// Actor that limits concurrent thumbnail generation to avoid overwhelming the system.
actor ThumbnailQueue {
    static let shared = ThumbnailQueue()
    
    private let maxConcurrent = 3
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    func enqueue(_ work: @Sendable () async -> Void) async {
        // Wait if at capacity
        if running >= maxConcurrent {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        
        running += 1
        await work()
        running -= 1
        
        // Resume next waiter
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

// MARK: - NSImage Extension for Tile Resizing

extension NSImage {
    func resizedForTile(maxSize: CGFloat) -> NSImage {
        let ratio = min(maxSize / size.width, maxSize / size.height)
        if ratio >= 1 { return self }
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
