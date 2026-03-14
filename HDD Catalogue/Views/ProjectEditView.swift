import SwiftUI
import SwiftData

/// Sheet for editing project details — name, client, type, summary.
struct ProjectEditView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UndoManagerService.self) private var undoService
    
    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var allProjects: [Project]
    
    @State private var displayName: String = ""
    @State private var projectType: String = ""
    @State private var aiSummary: String = ""
    @State private var selectedClientId: UUID?
    @State private var newClientName: String = ""
    @State private var showNewClientField = false
    @State private var editTags: [String] = []
    @State private var editNotes: String = ""
    @State private var editStatus: ProjectStatus = .new
    
    private let projectTypes = [
        "Web Design", "Video Edit", "Photography", "3D/Motion",
        "Development", "Branding", "Music/Audio", "Documentation", "Other"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Project")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Save") { save() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            Form {
                // Original folder name (read-only)
                LabeledContent("Folder") {
                    Text(project.folderName)
                        .foregroundStyle(.secondary)
                }
                
                // Display name (editable)
                TextField("Display Name", text: $displayName)
                
                // Drive info (read-only)
                if let drive = project.drive {
                    LabeledContent("Drive") {
                        HStack(spacing: 4) {
                            Image(systemName: drive.isConnected ? "externaldrive.fill" : "externaldrive")
                                .foregroundStyle(drive.isConnected ? .green : .gray)
                            Text(drive.name)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Project type
                Picker("Type", selection: $projectType) {
                    ForEach(projectTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.menu)
                
                // Client
                Section("Client") {
                    Picker("Assign to", selection: $selectedClientId) {
                        Text("Uncategorized").tag(nil as UUID?)
                        ForEach(clients, id: \.id) { client in
                            HStack {
                                Circle()
                                    .fill(client.color)
                                    .frame(width: 8, height: 8)
                                Text(client.name)
                            }
                            .tag(client.id as UUID?)
                        }
                    }
                    
                    // New client option
                    if showNewClientField {
                        HStack {
                            TextField("New client name", text: $newClientName)
                            Button("Add") {
                                createClient()
                            }
                            .disabled(newClientName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    
                    Button(showNewClientField ? "Cancel" : "+ New Client") {
                        showNewClientField.toggle()
                        newClientName = ""
                    }
                    .font(.caption)
                }
                
                // AI Summary
                Section("AI Summary") {
                    TextEditor(text: $aiSummary)
                        .frame(minHeight: 60)
                        .font(.body)
                }
                
                // Phase 2: Status
                Section("Status") {
                    Picker("Status", selection: $editStatus) {
                        ForEach(ProjectStatus.allCases) { status in
                            HStack {
                                Image(systemName: status.icon)
                                Text(status.rawValue)
                            }
                            .tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Phase 2: Tags
                Section("Tags") {
                    TagInputView(
                        tags: $editTags,
                        allTags: allExistingTags
                    )
                }
                
                // Phase 2: Notes
                Section("Notes") {
                    TextEditor(text: $editNotes)
                        .frame(minHeight: 60)
                        .font(.body)
                        .overlay(
                            Group {
                                if editNotes.isEmpty {
                                    Text("Personal notes about this project…")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                }
                
                // Phase 1: Detected NLEs (read-only)
                if !project.detectedNLEs.isEmpty {
                    Section("NLE Projects") {
                        ForEach(project.nleIcons, id: \.name) { nle in
                            HStack(spacing: 8) {
                                Image(systemName: nle.symbol)
                                    .foregroundStyle(.purple)
                                Text(nle.name)
                                Text(nle.abbreviation)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(.purple)
                            }
                        }
                        if let nleDate = project.nleProjectFileDate {
                            LabeledContent("NLE File Modified") {
                                Text(nleDate.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Phase 1: Camera sources (read-only)
                if !project.cameraSources.isEmpty {
                    Section("Camera Sources") {
                        ForEach(project.cameraSources, id: \.self) { camera in
                            HStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(.indigo)
                                Text(camera)
                            }
                        }
                        if project.hasDroneFootage {
                            HStack(spacing: 8) {
                                Image(systemName: "airplane")
                                    .foregroundStyle(.cyan)
                                Text("Drone/Aerial Footage")
                            }
                        }
                    }
                }
                
                // Phase 1: Shoot days (read-only)
                if project.shootDayCount > 0 {
                    Section("Shoot Days (\(project.shootDayCount))") {
                        ForEach(project.shootDayFolders, id: \.self) { folder in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.orange)
                                Text(folder)
                            }
                        }
                    }
                }
                
                // Phase 1: Media summary (read-only)
                if let summary = project.mediaSummary, !summary.isEmpty {
                    Section("Media Breakdown") {
                        if summary.videoCount > 0 {
                            LabeledContent("Video Files", value: "\(summary.videoCount)")
                        }
                        if summary.audioCount > 0 {
                            LabeledContent("Audio Files", value: "\(summary.audioCount)")
                        }
                        if summary.graphicsCount > 0 {
                            LabeledContent("Graphics", value: "\(summary.graphicsCount)")
                        }
                        if summary.fontCount > 0 {
                            LabeledContent("Fonts", value: "\(summary.fontCount)")
                        }
                        if summary.renderCount > 0 {
                            LabeledContent("Renders/Exports", value: "\(summary.renderCount)")
                        }
                    }
                }
                
                // Phase 1: Thumbnail regeneration
                if project.drive?.isConnected == true {
                    Section("Thumbnail") {
                        Button("Regenerate Video Thumbnail") {
                            Task {
                                let projectURL = URL(fileURLWithPath: project.folderPath)
                                if let data = await VideoThumbnailService.generateThumbnail(for: projectURL) {
                                    project.thumbnailData = data
                                    project.thumbnailType = .videoFrame
                                    try? modelContext.save()
                                }
                            }
                        }
                        .disabled(project.mediaSummary?.videoCount ?? 0 == 0)
                    }
                }
                
                // Metadata (read-only)
                Section("Info") {
                    LabeledContent("Size", value: project.formattedSize)
                    LabeledContent("Files", value: "\(project.fileCount)")
                    LabeledContent("Modified", value: project.formattedDate)
                    if project.isDelivered {
                        LabeledContent("Status") {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("Delivered")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    LabeledContent("Completeness") {
                        Text("\(Int(project.projectCompleteness * 100))%")
                            .foregroundStyle(project.projectCompleteness >= 0.9 ? .green : .secondary)
                    }
                    LabeledContent("Path") {
                        Text(project.folderPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(idealWidth: 480, minHeight: 600, idealHeight: 700, maxHeight: 800)
        .onAppear {
            displayName = project.displayName
            projectType = project.projectType
            aiSummary = project.aiSummary
            selectedClientId = project.client?.id
            editTags = project.tags
            editNotes = project.notes
            editStatus = project.projectStatus
        }
    }
    
    private var allExistingTags: [String] {
        Array(Set(allProjects.flatMap(\.tags))).sorted()
    }
    
    private func save() {
        // Snapshot old values for undo
        let oldSnapshot = UndoManagerService.ProjectSnapshot(
            displayName: project.displayName,
            projectType: project.projectType,
            aiSummary: project.aiSummary,
            isEdited: project.isEdited,
            clientId: project.client?.id
        )
        
        project.displayName = displayName
        project.projectType = projectType
        project.aiSummary = aiSummary
        project.isEdited = true
        project.tags = editTags
        project.notes = editNotes
        project.projectStatus = editStatus
        
        // Update client assignment
        if let clientId = selectedClientId {
            project.client = clients.first { $0.id == clientId }
        } else {
            project.client = nil
        }
        
        let newSnapshot = UndoManagerService.ProjectSnapshot(
            displayName: project.displayName,
            projectType: project.projectType,
            aiSummary: project.aiSummary,
            isEdited: project.isEdited,
            clientId: project.client?.id
        )
        
        undoService.registerProjectEdit(
            project: project,
            oldSnapshot: oldSnapshot,
            newSnapshot: newSnapshot,
            context: modelContext
        )
        
        try? modelContext.save()
        dismiss()
    }
    
    private func createClient() {
        let name = newClientName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        let client = Client(name: name)
        modelContext.insert(client)
        selectedClientId = client.id
        showNewClientField = false
        newClientName = ""
        
        try? modelContext.save()
    }
}
