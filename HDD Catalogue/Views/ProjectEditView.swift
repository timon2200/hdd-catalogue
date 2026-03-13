import SwiftUI
import SwiftData

/// Sheet for editing project details — name, client, type, summary.
struct ProjectEditView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Client.name) private var clients: [Client]
    
    @State private var displayName: String = ""
    @State private var projectType: String = ""
    @State private var aiSummary: String = ""
    @State private var selectedClientId: UUID?
    @State private var newClientName: String = ""
    @State private var showNewClientField = false
    
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
                Section("Notes") {
                    TextEditor(text: $aiSummary)
                        .frame(minHeight: 60)
                        .font(.body)
                }
                
                // Metadata (read-only)
                Section("Info") {
                    LabeledContent("Size", value: project.formattedSize)
                    LabeledContent("Files", value: "\(project.fileCount)")
                    LabeledContent("Modified", value: project.formattedDate)
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
        .frame(width: 480, height: 600)
        .onAppear {
            displayName = project.displayName
            projectType = project.projectType
            aiSummary = project.aiSummary
            selectedClientId = project.client?.id
        }
    }
    
    private func save() {
        project.displayName = displayName
        project.projectType = projectType
        project.aiSummary = aiSummary
        project.isEdited = true
        
        // Update client assignment
        if let clientId = selectedClientId {
            project.client = clients.first { $0.id == clientId }
        } else {
            project.client = nil
        }
        
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
