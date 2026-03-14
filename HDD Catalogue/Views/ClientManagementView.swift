import SwiftUI
import SwiftData

/// Full client management panel — rename, recolor, merge clients.
struct ClientManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UndoManagerService.self) private var undoService
    @Query(sort: \Client.name) private var clients: [Client]
    
    @State private var editingClient: Client?
    @State private var editName: String = ""
    @State private var editColorHex: String = ""
    @State private var mergeSource: Client?
    @State private var mergeTarget: Client?
    @State private var showMergeConfirm = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Clients")
                    .font(.headline)
                Spacer()
                Text("\(clients.count) clients")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
            }
            .padding()
            
            Divider()
            
            if clients.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No clients yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Clients are created automatically by AI\nor manually when editing projects.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                List {
                    ForEach(clients, id: \.id) { client in
                        clientRow(client)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            
            // Merge section
            if clients.count > 1 {
                Divider()
                mergeSection
            }
        }
        .frame(width: 500, height: 480)
        .alert("Merge Clients", isPresented: $showMergeConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Merge", role: .destructive) {
                performMerge()
            }
        } message: {
            if let source = mergeSource, let target = mergeTarget {
                Text("Move all \(source.projects.count) projects from \"\(source.name)\" to \"\(target.name)\" and delete \"\(source.name)\"?")
            }
        }
        .sheet(item: $editingClient) { client in
            editClientSheet(client)
        }
    }
    
    // MARK: - Client Row
    
    @ViewBuilder
    private func clientRow(_ client: Client) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(client.color)
                .frame(width: 14, height: 14)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name)
                    .fontWeight(.medium)
                Text("\(client.projects.count) projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if client.aiConfidence > 0 {
                Text("\(Int(client.aiConfidence * 100))% AI")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            
            Button {
                editingClient = client
                editName = client.name
                editColorHex = client.colorHex
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit client")
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Edit Sheet
    
    @ViewBuilder
    private func editClientSheet(_ client: Client) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Client")
                    .font(.headline)
                Spacer()
                Button("Cancel") { editingClient = nil }
                    .keyboardShortcut(.escape)
                Button("Save") {
                    let oldSnapshot = UndoManagerService.ClientSnapshot(
                        name: client.name,
                        colorHex: client.colorHex
                    )
                    let newName = editName.trimmingCharacters(in: .whitespaces)
                    client.name = newName
                    client.colorHex = editColorHex
                    let newSnapshot = UndoManagerService.ClientSnapshot(
                        name: newName,
                        colorHex: editColorHex
                    )
                    undoService.registerClientEdit(
                        client: client,
                        oldSnapshot: oldSnapshot,
                        newSnapshot: newSnapshot,
                        context: modelContext
                    )
                    try? modelContext.save()
                    editingClient = nil
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            
            Divider()
            
            Form {
                TextField("Client Name", text: $editName)
                
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 10), spacing: 8) {
                        ForEach(ColorPalette.colors, id: \.self) { hex in
                            Button {
                                editColorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? .gray)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if editColorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Section("Preview") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: editColorHex) ?? .gray)
                            .frame(width: 14, height: 14)
                        Text(editName.isEmpty ? "Client Name" : editName)
                            .foregroundStyle(editName.isEmpty ? .secondary : .primary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 360)
    }
    
    // MARK: - Merge Section
    
    private var mergeSection: some View {
        VStack(spacing: 8) {
            Text("Merge Clients")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                Picker("From", selection: $mergeSource) {
                    Text("Select…").tag(nil as Client?)
                    ForEach(clients, id: \.id) { client in
                        HStack {
                            Circle().fill(client.color).frame(width: 8, height: 8)
                            Text(client.name)
                        }
                        .tag(client as Client?)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                
                Picker("Into", selection: $mergeTarget) {
                    Text("Select…").tag(nil as Client?)
                    ForEach(clients.filter { $0.id != mergeSource?.id }, id: \.id) { client in
                        HStack {
                            Circle().fill(client.color).frame(width: 8, height: 8)
                            Text(client.name)
                        }
                        .tag(client as Client?)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Button("Merge") {
                    showMergeConfirm = true
                }
                .buttonStyle(.bordered)
                .disabled(mergeSource == nil || mergeTarget == nil || mergeSource?.id == mergeTarget?.id)
            }
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func performMerge() {
        guard let source = mergeSource, let target = mergeTarget else { return }
        
        let movedProjectIds = source.projects.map(\.id)
        
        // Reassign all projects from source to target
        for project in source.projects {
            project.client = target
        }
        
        // Register undo before deleting
        undoService.registerClientMerge(
            deletedClient: source,
            targetClient: target,
            movedProjectIds: movedProjectIds,
            context: modelContext
        )
        
        // Delete source client
        modelContext.delete(source)
        try? modelContext.save()
        
        mergeSource = nil
        mergeTarget = nil
    }
}
