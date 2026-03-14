import SwiftUI
import SwiftData
import ServiceManagement

/// Settings view for API key, scan preferences, and launch-at-login.
struct SettingsView: View {
    @State private var scanDepth: Int = 1
    @State private var loginItemError: String?
    
    @AppStorage("scanDepth") private var storedScanDepth = 1
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoScanOnMount") private var autoScanOnMount = true
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("enableVisualIndexing") private var enableVisualIndexing = true
    @AppStorage("ollamaModel") private var ollamaModel = "qwen3.5:0.8b"
    @AppStorage("ollamaReasoningModel") private var ollamaReasoningModel = "qwen3.5:4b"
    @State private var showRebuildConfirm = false
    @State private var ollamaAvailable = false
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            aiTab
                .tabItem {
                    Label("AI", systemImage: "brain")
                }
            
            scanTab
                .tabItem {
                    Label("Scanning", systemImage: "doc.viewfinder")
                }
        }
        .frame(width: 480, height: 380)
        .onAppear {
            scanDepth = storedScanDepth
        }
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
                
                if let error = loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                Toggle("Show Notifications", isOn: $showNotifications)
                
                Toggle("Auto-scan on Drive Mount", isOn: $autoScanOnMount)
            } header: {
                Text("Behavior")
            }
            
            Section {
                HStack {
                    Text("HDD Catalogue")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("Version 1.0")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }
            
            Section {
                Button(role: .destructive) {
                    showRebuildConfirm = true
                } label: {
                    Label("Rebuild Database", systemImage: "arrow.triangle.2.circlepath")
                }
                .alert("Rebuild Database?", isPresented: $showRebuildConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Rebuild", role: .destructive) {
                        rebuildDatabase()
                    }
                } message: {
                    Text("This will delete all catalogued projects, clients, and thumbnails. The app will quit and you'll need to re-scan your drives.\n\nFiles on disk are never affected.")
                }
                
                Text("Deletes all app data and restarts fresh. Use this to fix corrupted data or duplicate clients.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Danger Zone")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - AI Tab
    
    private var aiTab: some View {
        Form {
            Section {
                Picker("Vision Model", selection: $ollamaModel) {
                    ForEach(OllamaService.supportedModels) { model in
                        Text("\(model.name) (\(model.size))")
                            .tag(model.id)
                    }
                }
                Text("Used for image descriptions during deep indexing. Smaller = faster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Reasoning Model", selection: $ollamaReasoningModel) {
                    ForEach(OllamaService.supportedModels) { model in
                        Text("\(model.name) (\(model.size))")
                            .tag(model.id)
                    }
                }
                Text("Used for project categorization, duplicate detection, and AI search. Bigger = smarter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Circle()
                        .fill(ollamaAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(ollamaAvailable ? "Ollama is running" : "Ollama not detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check") {
                        Task {
                            let service = OllamaService()
                            service.currentModel = ollamaModel
                            await service.checkAvailability()
                            ollamaAvailable = service.isAvailable
                        }
                    }
                    .font(.caption)
                }
                
                Text("Install [Ollama](https://ollama.com) and pull models:\n`ollama pull qwen3.5:0.8b` (vision)\n`ollama pull qwen3.5:4b` (reasoning)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Local AI (Ollama + Qwen 3.5)")
            }
            
            Section {
                Toggle("Enable Visual Indexing", isOn: $enableVisualIndexing)
                
                Text("Project thumbnails are analyzed on-device using Apple Vision for visual search tags. Enables AI Visual Search (⌘⇧F) and Find Similar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Visual Search")
            }
            
            Section {
                Text("• All AI runs 100% locally via Ollama — no data leaves your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• AI analyzes folder names, sizes, and dates — never file contents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• Visual tagging uses Apple Vision (on-device, no network)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• You can manually override any AI suggestion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            Task {
                let service = OllamaService()
                service.currentModel = ollamaModel
                await service.checkAvailability()
                ollamaAvailable = service.isAvailable
            }
        }
    }
    
    // MARK: - Scan Tab
    
    private var scanTab: some View {
        Form {
            Section {
                Stepper("Scan Depth: \(scanDepth) levels", value: $scanDepth, in: 1...5)
                    .onChange(of: scanDepth) { _, newValue in
                        storedScanDepth = newValue
                    }
                
                Text("Level 1 = projects at drive root. Increase if projects are nested inside organization folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Folder Scanning")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Excluded directories:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(".Trash, .Spotlight-V100, .fseventsd, node_modules, .git, __pycache__")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Filters")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - Helpers
    
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Failed to update login item: \(error.localizedDescription)"
            // Revert the toggle on failure
            launchAtLogin = !enabled
        }
    }
    private func rebuildDatabase() {
        // Find and delete the SwiftData store files
        let config = ModelConfiguration("HDD_Catalogue", isStoredInMemoryOnly: false)
        let storeURL = config.url
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let fileURL = URL(fileURLWithPath: storeURL.path + suffix)
            try? fm.removeItem(at: fileURL)
        }
        
        // Quit the app so it restarts with a fresh store
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }
}

