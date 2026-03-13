import SwiftUI

/// Settings view for API key, scan preferences, and launch-at-login.
struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var scanDepth: Int = 2
    @State private var showAPIKey = false
    @State private var keySaved = false
    
    @AppStorage("scanDepth") private var storedScanDepth = 2
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoScanOnMount") private var autoScanOnMount = true
    @AppStorage("showNotifications") private var showNotifications = true
    
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
        .frame(width: 480, height: 340)
        .onAppear {
            apiKey = KeychainHelper.getAPIKey()
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
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - AI Tab
    
    private var aiTab: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if showAPIKey {
                            TextField("Gemini API Key", text: $apiKey)
                        } else {
                            SecureField("Gemini API Key", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    
                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                
                HStack {
                    if keySaved {
                        Label("Key saved securely in Keychain", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    
                    Spacer()
                    
                    Button("Save Key") {
                        KeychainHelper.saveAPIKey(apiKey)
                        keySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            keySaved = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Google Gemini API")
            } footer: {
                Text("Your API key is stored securely in the macOS Keychain. Get a free key at [aistudio.google.com](https://aistudio.google.com)")
            }
            
            Section {
                Text("• AI analyzes folder names, sizes, and dates — never file contents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• Data is sent to Google's Gemini API for categorization")
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
    }
    
    // MARK: - Scan Tab
    
    private var scanTab: some View {
        Form {
            Section {
                Stepper("Scan Depth: \(scanDepth) levels", value: $scanDepth, in: 1...5)
                    .onChange(of: scanDepth) { _, newValue in
                        storedScanDepth = newValue
                    }
                
                Text("How deep into each drive's folder structure to scan for projects.")
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
        // In a real app, use SMAppService.mainApp.register() / unregister()
        // Requires proper entitlements and signing
    }
}
