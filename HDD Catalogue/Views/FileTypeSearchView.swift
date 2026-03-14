import SwiftUI
import SwiftData

/// Phase 3: File Type Search — search for specific file extensions across all projects and drives.
struct FileTypeSearchView: View {
    let projects: [Project]
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchExtension = ""
    @State private var selectedQuickPick: String?
    
    private let quickPicks: [(label: String, ext: String, icon: String)] = [
        ("Premiere", "prproj", "film"),
        ("Final Cut", "fcpbundle", "film"),
        ("DaVinci", "drp", "film"),
        ("After Effects", "aep", "sparkles"),
        ("Motion Graphic", "mogrt", "wand.and.stars"),
        ("RED RAW", "r3d", "camera.fill"),
        ("BRAW", "braw", "camera.fill"),
        ("ProRes", "mov", "video"),
        ("MP4", "mp4", "video"),
        ("MXF", "mxf", "video"),
        ("WAV", "wav", "waveform"),
        ("PSD", "psd", "paintbrush"),
        ("EXR", "exr", "photo"),
        ("LUT", "cube", "paintpalette"),
    ]
    
    private var activeExtension: String {
        let ext = (selectedQuickPick ?? searchExtension).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
    }
    
    /// All indexed extensions for autocomplete.
    private var allIndexedExtensions: [String] {
        var extSet = Set<String>()
        for project in projects {
            for file in project.mediaFiles {
                extSet.insert(file.fileExtension)
            }
        }
        return Array(extSet).sorted()
    }
    
    /// Autocomplete suggestions.
    private var suggestions: [String] {
        guard !searchExtension.isEmpty else { return [] }
        let query = searchExtension.lowercased().replacingOccurrences(of: ".", with: "")
        return allIndexedExtensions.filter { $0.contains(query) }.prefix(8).map { $0 }
    }
    
    /// Results grouped by drive.
    private var results: [(drive: Drive, projectResults: [(project: Project, files: [MediaFile])])] {
        guard !activeExtension.isEmpty else { return [] }
        
        var byDrive: [UUID: (drive: Drive, projectResults: [(project: Project, files: [MediaFile])])] = [:]
        
        for project in projects {
            let matchingFiles = project.mediaFiles.filter { $0.fileExtension == activeExtension }
            guard !matchingFiles.isEmpty else { continue }
            
            guard let drive = project.drive else { continue }
            
            if byDrive[drive.id] == nil {
                byDrive[drive.id] = (drive, [])
            }
            byDrive[drive.id]?.projectResults.append((project, matchingFiles))
        }
        
        return byDrive.values
            .sorted { $0.projectResults.count > $1.projectResults.count }
    }
    
    private var totalFileCount: Int {
        results.reduce(0) { $0 + $1.projectResults.reduce(0) { $0 + $1.files.count } }
    }
    
    private var totalFileSize: Int64 {
        results.reduce(Int64(0)) { outer, driveGroup in
            outer + driveGroup.projectResults.reduce(Int64(0)) { inner, projectResult in
                inner + projectResult.files.reduce(Int64(0)) { acc, file in acc + file.fileSize }
            }
        }
    }
    
    private var hasDeepIndexedProjects: Bool {
        projects.contains { $0.isDeepIndexed }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("File Type Search")
                        .font(.system(size: 18, weight: .bold))
                    Text("Find specific file types across all projects and drives")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(20)
            
            Divider()
            
            if !hasDeepIndexedProjects {
                // Empty state: needs deep indexing
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.badge.automatic")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Deep indexing required")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Run Deep Index from the toolbar to index all files\nacross your projects for file type search.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                // Search bar
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        
                        TextField("Enter file extension (e.g. prproj, mov, r3d)", text: $searchExtension)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onChange(of: searchExtension) { _, _ in
                                selectedQuickPick = nil
                            }
                        
                        if !searchExtension.isEmpty {
                            Button {
                                searchExtension = ""
                                selectedQuickPick = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    
                    // Suggestions
                    if !suggestions.isEmpty && selectedQuickPick == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestions, id: \.self) { ext in
                                    Button {
                                        searchExtension = ext
                                    } label: {
                                        Text(".\(ext)")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.blue.opacity(0.1), in: Capsule())
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Quick picks
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(quickPicks, id: \.ext) { pick in
                                Button {
                                    if selectedQuickPick == pick.ext {
                                        selectedQuickPick = nil
                                    } else {
                                        selectedQuickPick = pick.ext
                                        searchExtension = ""
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: pick.icon)
                                            .font(.system(size: 9))
                                        Text(".\(pick.ext)")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        selectedQuickPick == pick.ext ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedQuickPick == pick.ext ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
                                    )
                                    .foregroundStyle(selectedQuickPick == pick.ext ? .primary : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                // Results
                if !activeExtension.isEmpty {
                    // Stats bar
                    if totalFileCount > 0 {
                        HStack(spacing: 16) {
                            Label("\(totalFileCount) files", systemImage: "doc.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Label(ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file), systemImage: "externaldrive")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Label("\(results.count) drives", systemImage: "externaldrive.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }
                    
                    ScrollView {
                        if results.isEmpty {
                            VStack(spacing: 8) {
                                Spacer(minLength: 30)
                                Image(systemName: "doc.questionmark")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.tertiary)
                                Text("No .\(activeExtension) files found")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 30)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(results, id: \.drive.id) { driveGroup in
                                    driveResultSection(driveGroup)
                                }
                            }
                            .padding(20)
                        }
                    }
                } else {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("Type an extension or pick one above")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Drive Result Section
    
    private func driveResultSection(_ group: (drive: Drive, projectResults: [(project: Project, files: [MediaFile])])) -> some View {
        let totalFiles = group.projectResults.reduce(0) { $0 + $1.files.count }
        let totalSize = group.projectResults.reduce(Int64(0)) { $0 + $1.files.reduce(Int64(0)) { $0 + $1.fileSize } }
        
        return VStack(alignment: .leading, spacing: 8) {
            // Drive header
            HStack(spacing: 8) {
                Image(systemName: group.drive.isConnected ? "externaldrive.fill" : "externaldrive")
                    .font(.system(size: 12))
                    .foregroundStyle(group.drive.isConnected ? .blue : .gray)
                Text(group.drive.name)
                    .font(.system(size: 13, weight: .bold))
                
                if !group.drive.isConnected {
                    Text("Disconnected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.1), in: Capsule())
                }
                
                Spacer()
                
                Text("\(totalFiles) files")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            
            // Project rows
            VStack(spacing: 1) {
                ForEach(group.projectResults, id: \.project.id) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.project.client?.color ?? .gray)
                            .frame(width: 6, height: 6)
                        
                        Text(item.project.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(item.files.count) files")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                        
                        let size = item.files.reduce(Int64(0)) { $0 + $1.fileSize }
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 65, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.02))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 0.5)
            )
        }
    }
}
