import SwiftUI
import SwiftData

/// Three-tab picker for project thumbnails: Image Drop, Emoji Search, SF Symbol Icon.
struct ThumbnailPickerView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var emojiSearch = ""
    @State private var isDropTargeted = false
    @State private var selectedSymbolCategory = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Change Thumbnail")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
            }
            .padding()
            
            // Current thumbnail preview
            currentThumbnailPreview
                .padding(.bottom, 12)
            
            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Drop Image").tag(0)
                Text("Emoji").tag(1)
                Text("Icon").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Tab content
            TabView(selection: $selectedTab) {
                imageDropTab.tag(0)
                emojiTab.tag(1)
                iconTab.tag(2)
            }
            .frame(minHeight: 300)
            
            Divider()
            
            // Reset button
            HStack {
                Button("Reset to Default") {
                    project.thumbnailType = .auto
                    project.thumbnailData = nil
                    project.thumbnailEmoji = nil
                    project.thumbnailIconName = nil
                    try? modelContext.save()
                }
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
        }
        .frame(width: 420, height: 520)
    }
    
    // MARK: - Current Preview
    
    private var currentThumbnailPreview: some View {
        VStack(spacing: 8) {
            Group {
                switch project.thumbnailType {
                case .image, .videoFrame:
                    if let data = project.thumbnailData, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                case .emoji:
                    Text(project.resolvedThumbnailEmoji)
                        .font(.system(size: 48))
                case .icon:
                    Image(systemName: project.thumbnailIconName ?? "folder.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(project.client?.color ?? .blue)
                case .auto:
                    Text(project.autoThumbnailEmoji)
                        .font(.system(size: 48))
                }
            }
            .frame(width: 64, height: 64)
            
            Text(project.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Image Drop Tab
    
    private var imageDropTab: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .foregroundStyle(isDropTargeted ? Color.blue : Color.gray.opacity(0.3))
                    .background(
                        isDropTargeted ? Color.blue.opacity(0.05) : .clear,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    
                    Text("Drop an image here")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("or drag an image from Finder")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier("public.image") {
                        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                            if let data = data, let thumb = ThumbnailManager.processDroppedImage(data) {
                                DispatchQueue.main.async {
                                    project.thumbnailData = thumb
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
    }
    
    // MARK: - Emoji Tab
    
    private var emojiTab: some View {
        VStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search emoji…", text: $emojiSearch)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Emoji grid
            ScrollView {
                let filteredCategories = emojiSearch.isEmpty
                    ? ThumbnailManager.emojiCategories
                    : ThumbnailManager.emojiCategories.filter { $0.name.lowercased().contains(emojiSearch.lowercased()) }
                
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 8), spacing: 8) {
                    if !emojiSearch.isEmpty && filteredCategories.isEmpty {
                        // Show all emojis when search doesn't match a category
                        ForEach(ThumbnailManager.searchEmojis(""), id: \.self) { emoji in
                            emojiButton(emoji)
                        }
                    } else {
                        ForEach(filteredCategories, id: \.name) { category in
                            Section {
                                ForEach(category.emojis, id: \.self) { emoji in
                                    emojiButton(emoji)
                                }
                            } header: {
                                Text(category.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }
    
    private func emojiButton(_ emoji: String) -> some View {
        Button {
            project.thumbnailEmoji = emoji
            project.thumbnailType = .emoji
            try? modelContext.save()
        } label: {
            Text(emoji)
                .font(.system(size: 24))
                .frame(width: 40, height: 40)
                .background(
                    project.thumbnailEmoji == emoji && project.thumbnailType == .emoji
                    ? Color.blue.opacity(0.2)
                    : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Icon Tab (SF Symbols)
    
    private var iconTab: some View {
        VStack(spacing: 12) {
            // Category picker
            Picker("Category", selection: $selectedSymbolCategory) {
                ForEach(0..<ThumbnailManager.sfSymbolCategories.count, id: \.self) { index in
                    Text(ThumbnailManager.sfSymbolCategories[index].name).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Icon grid
            ScrollView {
                let category = ThumbnailManager.sfSymbolCategories[selectedSymbolCategory]
                
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(56)), count: 6), spacing: 12) {
                    ForEach(category.symbols, id: \.self) { symbol in
                        symbolButton(symbol)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }
    
    private func symbolButton(_ symbol: String) -> some View {
        let isSelected = project.thumbnailIconName == symbol && project.thumbnailType == .icon
        let bgColor: Color = isSelected ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1)
        let strokeColor: Color = isSelected ? Color.blue.opacity(0.5) : Color.clear
        let tintColor: Color = project.client?.color ?? .blue
        
        return Button {
            project.thumbnailIconName = symbol
            project.thumbnailType = .icon
            try? modelContext.save()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(tintColor)
                .frame(width: 48, height: 48)
                .background(bgColor, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(strokeColor, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
