import SwiftUI
import SwiftData
import ServiceManagement

/// Settings view for API key, scan preferences, and launch-at-login.
struct SettingsView: View {
    var checkForUpdatesAction: (() -> Void)?
    var canCheckForUpdates: Bool?
    @State private var scanDepth: Int = 1
    @State private var loginItemError: String?
    
    @AppStorage("scanDepth") private var storedScanDepth = 1
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoScanOnMount") private var autoScanOnMount = true
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("enableVisualIndexing") private var enableVisualIndexing = true
    @AppStorage("autoCheckForUpdates") private var autoCheckForUpdates = true
    @AppStorage("ollamaModel") private var ollamaModel = "qwen3.5:0.8b"
    @AppStorage("ollamaReasoningModel") private var ollamaReasoningModel = "qwen3.5:4b"
    @AppStorage("deepScanMode") private var deepScanMode = "frames"
    @State private var showRebuildConfirm = false
    @State private var setupService = OllamaSetupService()
    @State private var showUninstallConfirm = false
    @State private var showDeleteModelConfirm: String?
    @State private var showSetupLog = false
    @State private var isQuickSetupRunning = false
    
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
        .frame(width: 520, height: 520)
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
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                        .foregroundStyle(.secondary)
                }
                
                Button("Check for Updates…") {
                    checkForUpdatesAction?()
                }
                .disabled(!(canCheckForUpdates ?? true))
                
                Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
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
            // Section 1: Ollama Runtime
            ollamaRuntimeSection
            
            // Section 2: Model Management
            modelManagementSection
            
            // Section 3: Model Selection
            modelSelectionSection
            
            // Section 4: Visual Search
            Section {
                Toggle("Enable Visual Indexing", isOn: $enableVisualIndexing)
                
                Text("Project thumbnails are analyzed on-device using Apple Vision for visual search tags. Enables AI Visual Search (⌘⇧F) and Find Similar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Visual Search")
            }
            
            // Section 5: Deep Indexing Mode
            Section {
                Picker("Video Analysis", selection: $deepScanMode) {
                    Text("Frames Only").tag("frames")
                    Text("Enhanced Motion").tag("motion")
                }
                .pickerStyle(.radioGroup)
                
                if deepScanMode == "frames" {
                    Text("Sends 2 keyframes (start + end) to the AI. Fast, works well for static shots.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sends a short downscaled video clip to the AI for real motion understanding. Slower but accurately detects camera movement, pans, tilts, and tracking shots.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Deep Indexing")
            }
            
            // Section 5: Privacy
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
            Task { await setupService.refreshStatus() }
        }
    }
    
    // MARK: - Ollama Runtime Section
    
    private var ollamaRuntimeSection: some View {
        Section {
            // Status row
            HStack(spacing: 8) {
                Image(systemName: ollamaStatusIcon)
                    .foregroundStyle(ollamaStatusColor)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(ollamaStatusText)
                        .font(.callout)
                        .fontWeight(.medium)
                    if let version = setupService.ollamaVersion, setupService.ollamaInstalled {
                        Text("Version \(version)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                if setupService.isInstallingOllama {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if setupService.isUninstallingOllama {
                    ProgressView()
                        .controlSize(.small)
                    Text("Removing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Action buttons
            HStack(spacing: 8) {
                if !setupService.ollamaInstalled {
                    // Not installed — show Install + Quick Setup
                    Button {
                        Task { await setupService.installOllama() }
                    } label: {
                        Label("Install Ollama", systemImage: "arrow.down.circle")
                    }
                    .disabled(setupService.isInstallingOllama)
                    
                    Button {
                        isQuickSetupRunning = true
                        Task {
                            await setupService.installEverything()
                            isQuickSetupRunning = false
                        }
                    } label: {
                        Label("Install Everything", systemImage: "sparkles")
                    }
                    .disabled(setupService.isInstallingOllama || isQuickSetupRunning)
                    .help("Install Ollama + download default AI models (qwen3.5:0.8b + qwen3.5:4b)")
                } else {
                    // Installed — show Start/Stop + Uninstall
                    if setupService.ollamaRunning {
                        Button {
                            Task { await setupService.stopServer() }
                        } label: {
                            Label("Stop Server", systemImage: "stop.circle")
                        }
                    } else {
                        Button {
                            Task { await setupService.startServer() }
                        } label: {
                            Label("Start Server", systemImage: "play.circle")
                        }
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        showUninstallConfirm = true
                    } label: {
                        Label("Uninstall", systemImage: "trash")
                    }
                    .alert("Uninstall Ollama?", isPresented: $showUninstallConfirm) {
                        Button("Cancel", role: .cancel) { }
                        Button("Uninstall", role: .destructive) {
                            Task { await setupService.uninstallOllama() }
                        }
                    } message: {
                        Text("This will remove Ollama and all downloaded models (~/.ollama). You can reinstall at any time.")
                    }
                }
            }
            
            // Setup log toggle
            if !setupService.setupLog.isEmpty {
                DisclosureGroup("Setup Log", isExpanded: $showSetupLog) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(setupService.setupLog) { entry in
                                HStack(spacing: 4) {
                                    Image(systemName: entry.type.icon)
                                        .font(.caption2)
                                        .foregroundStyle(logColor(for: entry.type))
                                    Text(entry.message)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 80)
                }
                .font(.caption)
            }
        } header: {
            Text("Ollama Runtime")
        }
    }
    
    // MARK: - Model Management Section
    
    private var modelManagementSection: some View {
        Section {
            ForEach(OllamaService.supportedModels) { model in
                modelRow(for: model)
            }
            
            // Show any installed models that aren't in the supported list
            let extraModels = setupService.installedModels.filter { installed in
                !OllamaService.supportedModels.contains(where: { supported in
                    installed.name.hasPrefix(supported.id)
                })
            }
            if !extraModels.isEmpty {
                Divider()
                ForEach(extraModels) { installed in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(installed.name)
                                .font(.callout)
                            Text(installed.formattedSize)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        
                        Button(role: .destructive) {
                            showDeleteModelConfirm = installed.name
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            HStack {
                Text("AI Models")
                Spacer()
                if setupService.ollamaRunning {
                    Button {
                        Task { await setupService.fetchInstalledModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh model list")
                }
            }
        }
        .alert("Delete Model?", isPresented: Binding(
            get: { showDeleteModelConfirm != nil },
            set: { if !$0 { showDeleteModelConfirm = nil } }
        )) {
            Button("Cancel", role: .cancel) { showDeleteModelConfirm = nil }
            Button("Delete", role: .destructive) {
                if let model = showDeleteModelConfirm {
                    Task { await setupService.deleteModel(model) }
                }
                showDeleteModelConfirm = nil
            }
        } message: {
            Text("Delete \(showDeleteModelConfirm ?? "this model")? You can re-download it later.")
        }
    }
    
    // MARK: - Model Row
    
    @ViewBuilder
    private func modelRow(for model: OllamaModel) -> some View {
        let isInstalled = setupService.installedModels.contains(where: { $0.name.hasPrefix(model.id) })
        let progress = setupService.pullProgress[model.id]
        
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(model.name)
                            .font(.callout)
                            .fontWeight(.medium)
                        Text(model.size)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                    Text(model.description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                if let progress = progress {
                    // Currently downloading
                    if progress.isDownloading {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(progress.percentString)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(progress.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else if isInstalled {
                    // Installed
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        
                        Button(role: .destructive) {
                            showDeleteModelConfirm = model.id
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                } else if setupService.ollamaRunning {
                    // Not installed but Ollama is running
                    Button {
                        Task { await setupService.pullModel(model.id) }
                    } label: {
                        Label("Install", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                } else {
                    // Not installed and Ollama not running
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            }
            
            // Progress bar for downloading
            if let progress = progress, progress.isDownloading {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
            }
        }
    }
    
    // MARK: - Model Selection Section
    
    private var modelSelectionSection: some View {
        Section {
            let installedIds = Set(setupService.installedModels.map { installedModel -> String in
                // Match to supported model IDs
                for supported in OllamaService.supportedModels {
                    if installedModel.name.hasPrefix(supported.id) {
                        return supported.id
                    }
                }
                return installedModel.name
            })
            
            Picker("Vision Model", selection: $ollamaModel) {
                ForEach(OllamaService.supportedModels) { model in
                    HStack {
                        Text("\(model.name) (\(model.size))")
                        if !installedIds.contains(model.id) {
                            Text("(not installed)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(model.id)
                }
            }
            Text("Used for image descriptions during deep indexing. Smaller = faster.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Picker("Reasoning Model", selection: $ollamaReasoningModel) {
                ForEach(OllamaService.supportedModels) { model in
                    HStack {
                        Text("\(model.name) (\(model.size))")
                        if !installedIds.contains(model.id) {
                            Text("(not installed)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(model.id)
                }
            }
            Text("Used for project categorization, duplicate detection, and AI search. Bigger = smarter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Active Models")
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
    
    // MARK: - Computed Properties
    
    private var ollamaStatusIcon: String {
        if setupService.ollamaInstalled && setupService.ollamaRunning {
            return "checkmark.circle.fill"
        } else if setupService.ollamaInstalled {
            return "exclamationmark.triangle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }
    
    private var ollamaStatusColor: Color {
        if setupService.ollamaInstalled && setupService.ollamaRunning {
            return .green
        } else if setupService.ollamaInstalled {
            return .orange
        } else {
            return .red
        }
    }
    
    private var ollamaStatusText: String {
        if setupService.ollamaInstalled && setupService.ollamaRunning {
            return "Installed & Running"
        } else if setupService.ollamaInstalled {
            return "Installed — Server Stopped"
        } else {
            return "Not Installed"
        }
    }
    
    private func logColor(for type: SetupLogEntry.LogType) -> Color {
        switch type {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
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
