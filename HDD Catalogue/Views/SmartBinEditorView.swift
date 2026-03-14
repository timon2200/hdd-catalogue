import SwiftUI
import SwiftData

/// Sheet for creating or editing a Smart Bin's criteria.
struct SmartBinEditorView: View {
    @Bindable var smartBin: SmartBin
    let isNew: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var projects: [Project]
    
    @State private var name: String = ""
    @State private var icon: String = "tray.full"
    @State private var criteria: SmartBinCriteria = SmartBinCriteria()
    
    private let iconOptions = [
        "tray.full", "star.fill", "flame.fill", "bolt.fill",
        "clock.fill", "folder.fill", "tag.fill", "camera.fill",
        "film", "waveform", "archivebox", "arrow.triangle.2.circlepath"
    ]
    
    private let nleOptions = [
        "Premiere Pro", "Final Cut Pro", "DaVinci Resolve",
        "After Effects", "Adobe Audition", "Motion Graphics"
    ]
    
    private let sizePresets: [(label: String, bytes: Int64)] = [
        ("Any", 0),
        ("> 100 MB", 100_000_000),
        ("> 500 MB", 500_000_000),
        ("> 1 GB", 1_000_000_000),
        ("> 5 GB", 5_000_000_000),
        ("> 10 GB", 10_000_000_000),
    ]
    
    private var matchCount: Int {
        let bin = SmartBin(name: name, icon: icon, criteria: criteria)
        return bin.matchingProjects(from: Array(projects)).count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New Smart Bin" : "Edit Smart Bin")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button(isNew ? "Create" : "Save") { save() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            
            Divider()
            
            Form {
                // Name & icon
                Section("Name & Icon") {
                    TextField("Bin name", text: $name)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 36))], spacing: 8) {
                        ForEach(iconOptions, id: \.self) { iconName in
                            Button {
                                icon = iconName
                            } label: {
                                Image(systemName: iconName)
                                    .font(.title3)
                                    .frame(width: 32, height: 32)
                                    .background(icon == iconName ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(icon == iconName ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Status criteria
                Section("Status") {
                    let statuses = criteria.statusValues ?? []
                    ForEach(ProjectStatus.allCases) { status in
                        Toggle(isOn: Binding(
                            get: { statuses.contains(status.rawValue) },
                            set: { isOn in
                                var current = criteria.statusValues ?? []
                                if isOn { current.append(status.rawValue) }
                                else { current.removeAll { $0 == status.rawValue } }
                                criteria.statusValues = current.isEmpty ? nil : current
                            }
                        )) {
                            HStack {
                                Image(systemName: status.icon)
                                    .foregroundStyle(status.color)
                                Text(status.rawValue)
                            }
                        }
                    }
                }
                
                // NLE criteria
                Section("NLE Types") {
                    let nles = criteria.nleTypes ?? []
                    ForEach(nleOptions, id: \.self) { nle in
                        Toggle(isOn: Binding(
                            get: { nles.contains(nle) },
                            set: { isOn in
                                var current = criteria.nleTypes ?? []
                                if isOn { current.append(nle) }
                                else { current.removeAll { $0 == nle } }
                                criteria.nleTypes = current.isEmpty ? nil : current
                            }
                        )) {
                            Text(nle)
                        }
                    }
                }
                
                // Size criteria
                Section("Minimum Size") {
                    Picker("Min size", selection: Binding(
                        get: { criteria.minSizeBytes ?? 0 },
                        set: { criteria.minSizeBytes = $0 > 0 ? $0 : nil }
                    )) {
                        ForEach(sizePresets, id: \.bytes) { preset in
                            Text(preset.label).tag(preset.bytes)
                        }
                    }
                }
                
                // Search text
                Section("Contains Text") {
                    TextField("Search text (optional)", text: Binding(
                        get: { criteria.searchText ?? "" },
                        set: { criteria.searchText = $0.isEmpty ? nil : $0 }
                    ))
                }
                
                // Preview
                Section {
                    HStack {
                        Image(systemName: "eye")
                            .foregroundStyle(.secondary)
                        Text("\(matchCount) projects match")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(matchCount > 0 ? .primary : .secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(idealWidth: 420, minHeight: 500, idealHeight: 600, maxHeight: 700)
        .onAppear {
            name = smartBin.name
            icon = smartBin.icon
            criteria = smartBin.criteria
        }
    }
    
    private func save() {
        smartBin.name = name.trimmingCharacters(in: .whitespaces)
        smartBin.icon = icon
        smartBin.criteria = criteria
        
        if isNew {
            modelContext.insert(smartBin)
        }
        
        try? modelContext.save()
        dismiss()
    }
}
