import Foundation

/// Manages Ollama installation, server lifecycle, and model pulling/deletion.
/// Runs shell commands directly (app is non-sandboxed).
@Observable
final class OllamaSetupService {
    
    // MARK: - Observable State
    
    var ollamaInstalled: Bool = false
    var ollamaRunning: Bool = false
    var ollamaVersion: String?
    var installedModels: [InstalledModel] = []
    var pullProgress: [String: PullProgress] = [:]
    var setupLog: [SetupLogEntry] = []
    var isInstallingOllama: Bool = false
    var isUninstallingOllama: Bool = false
    
    // MARK: - Constants
    
    private let ollamaPaths = [
        "/usr/local/bin/ollama",
        "/opt/homebrew/bin/ollama",
        "/usr/bin/ollama"
    ]
    
    private let baseURL = "http://localhost:11434"
    
    // MARK: - Detection
    
    /// Find the ollama binary path, or nil if not installed.
    func ollamaPath() -> String? {
        for path in ollamaPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        // Also check via `which`
        if let path = runShellSync("which ollama"),
           !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }
    
    /// Full status refresh: installed? running? which models?
    func refreshStatus() async {
        let installed = ollamaPath() != nil
        await MainActor.run { ollamaInstalled = installed }
        
        if installed {
            // Get version
            if let version = runShellSync("\(ollamaPath()!) --version") {
                let cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)
                // Typically "ollama version is X.X.X"
                let versionString = cleaned.components(separatedBy: " ").last ?? cleaned
                await MainActor.run { ollamaVersion = versionString }
            }
            
            // Check if server is running
            let running = await checkServerRunning()
            await MainActor.run { ollamaRunning = running }
            
            if running {
                await fetchInstalledModels()
            }
        } else {
            await MainActor.run {
                ollamaRunning = false
                ollamaVersion = nil
                installedModels = []
            }
        }
    }
    
    /// Check if the Ollama API responds.
    private func checkServerRunning() async -> Bool {
        do {
            let url = URL(string: "\(baseURL)/api/tags")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    // MARK: - Ollama Installation
    
    /// Install Ollama using the official install script.
    func installOllama() async {
        await MainActor.run {
            isInstallingOllama = true
            addLog("Starting Ollama installation…", type: .info)
        }
        
        // Use the official macOS install approach — download the app bundle
        // The install.sh script works on Linux; on macOS Ollama distributes as an app.
        // We'll download the CLI directly from the official release.
        
        // Method: Use the install script which handles macOS too
        let result = await runShellAsync("curl -fsSL https://ollama.com/install.sh | sh")
        
        if let output = result {
            await MainActor.run {
                if output.contains("error") || output.contains("Error") {
                    addLog("Installation may have encountered issues: \(output.prefix(200))", type: .error)
                } else {
                    addLog("Ollama installed successfully", type: .success)
                }
            }
        } else {
            await MainActor.run {
                addLog("Installation command completed", type: .info)
            }
        }
        
        // Brief delay then refresh
        try? await Task.sleep(for: .seconds(1))
        await refreshStatus()
        
        // Auto-start if installed but not running
        if ollamaInstalled && !ollamaRunning {
            await startServer()
        }
        
        await MainActor.run { isInstallingOllama = false }
    }
    
    /// Uninstall Ollama — remove binary and data.
    func uninstallOllama() async {
        await MainActor.run {
            isUninstallingOllama = true
            addLog("Uninstalling Ollama…", type: .info)
        }
        
        // Stop server first
        await stopServer()
        
        // Remove the binary
        if let path = ollamaPath() {
            _ = runShellSync("rm -f \"\(path)\"")
        }
        
        // Remove data directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let ollamaDataDir = "\(homeDir)/.ollama"
        if FileManager.default.fileExists(atPath: ollamaDataDir) {
            _ = runShellSync("rm -rf \"\(ollamaDataDir)\"")
            await MainActor.run {
                addLog("Removed Ollama data (~/.ollama)", type: .info)
            }
        }
        
        await refreshStatus()
        await MainActor.run {
            isUninstallingOllama = false
            addLog("Ollama uninstalled", type: .success)
        }
    }
    
    // MARK: - Server Control
    
    /// Start the Ollama server in background.
    func startServer() async {
        guard ollamaInstalled, let path = ollamaPath() else { return }
        
        await MainActor.run { addLog("Starting Ollama server…", type: .info) }
        
        // Launch in background
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
        
        // Wait for server to start (up to 10 seconds)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if await checkServerRunning() {
                await MainActor.run {
                    ollamaRunning = true
                    addLog("Ollama server is running", type: .success)
                }
                await fetchInstalledModels()
                return
            }
        }
        
        await MainActor.run {
            addLog("Server may not have started — check manually", type: .warning)
        }
    }
    
    /// Stop the Ollama server.
    func stopServer() async {
        await MainActor.run { addLog("Stopping Ollama server…", type: .info) }
        _ = runShellSync("pkill -f 'ollama serve'")
        try? await Task.sleep(for: .seconds(1))
        let running = await checkServerRunning()
        await MainActor.run {
            ollamaRunning = running
            if !running {
                addLog("Ollama server stopped", type: .success)
            }
        }
    }
    
    // MARK: - Model Management
    
    /// Fetch the list of installed models from the Ollama API.
    func fetchInstalledModels() async {
        do {
            let url = URL(string: "\(baseURL)/api/tags")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: request)
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                return
            }
            
            let installed = models.compactMap { model -> InstalledModel? in
                guard let name = model["name"] as? String else { return nil }
                let size = model["size"] as? Int64 ?? 0
                let modified = model["modified_at"] as? String
                let details = model["details"] as? [String: Any]
                let parameterSize = details?["parameter_size"] as? String
                let family = details?["family"] as? String
                
                return InstalledModel(
                    name: name,
                    size: size,
                    modifiedAt: modified,
                    parameterSize: parameterSize,
                    family: family
                )
            }
            
            await MainActor.run { installedModels = installed }
        } catch {
            // Silently fail — models just won't show
        }
    }
    
    /// Pull (download) a model with streaming progress.
    func pullModel(_ modelId: String) async {
        guard ollamaRunning else {
            await MainActor.run {
                addLog("Cannot pull model — Ollama is not running", type: .error)
            }
            return
        }
        
        await MainActor.run {
            pullProgress[modelId] = PullProgress(status: "Starting download…", completed: 0, total: 0)
            addLog("Pulling model: \(modelId)…", type: .info)
        }
        
        do {
            let url = URL(string: "\(baseURL)/api/pull")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 3600 // Models can be large
            
            let payload: [String: Any] = [
                "name": modelId,
                "stream": true
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run {
                    pullProgress[modelId] = PullProgress(status: "Error: bad response", completed: 0, total: 0)
                    addLog("Failed to pull \(modelId): bad HTTP response", type: .error)
                }
                return
            }
            
            // Stream the response line by line — each line is a JSON object
            var buffer = ""
            for try await byte in asyncBytes {
                let char = Character(UnicodeScalar(byte))
                if char == "\n" {
                    if !buffer.isEmpty, let lineData = buffer.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                        
                        let status = json["status"] as? String ?? ""
                        let completed = json["completed"] as? Int64 ?? 0
                        let total = json["total"] as? Int64 ?? 0
                        
                        await MainActor.run {
                            pullProgress[modelId] = PullProgress(
                                status: status,
                                completed: completed,
                                total: total
                            )
                        }
                    }
                    buffer = ""
                } else {
                    buffer.append(char)
                }
            }
            
            // Done
            await MainActor.run {
                pullProgress.removeValue(forKey: modelId)
                addLog("Model \(modelId) pulled successfully", type: .success)
            }
            
            // Refresh model list
            await fetchInstalledModels()
            
        } catch {
            await MainActor.run {
                pullProgress[modelId] = PullProgress(status: "Error: \(error.localizedDescription)", completed: 0, total: 0)
                addLog("Failed to pull \(modelId): \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    /// Delete an installed model.
    func deleteModel(_ modelName: String) async {
        guard ollamaRunning else { return }
        
        await MainActor.run {
            addLog("Deleting model: \(modelName)…", type: .info)
        }
        
        do {
            let url = URL(string: "\(baseURL)/api/delete")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["name": modelName])
            request.timeoutInterval = 30
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await MainActor.run {
                    addLog("Model \(modelName) deleted", type: .success)
                }
            } else {
                await MainActor.run {
                    addLog("Failed to delete \(modelName)", type: .error)
                }
            }
        } catch {
            await MainActor.run {
                addLog("Error deleting \(modelName): \(error.localizedDescription)", type: .error)
            }
        }
        
        await fetchInstalledModels()
    }
    
    // MARK: - Quick Setup
    
    /// One-click install: Ollama + both default models.
    func installEverything() async {
        await MainActor.run {
            addLog("🚀 Quick Setup: Installing Ollama + default models…", type: .info)
        }
        
        if !ollamaInstalled {
            await installOllama()
        }
        
        if !ollamaRunning {
            await startServer()
        }
        
        guard ollamaRunning else {
            await MainActor.run {
                addLog("Cannot pull models — Ollama failed to start", type: .error)
            }
            return
        }
        
        // Pull default vision model
        let visionModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? "qwen3.5:0.8b"
        if !isModelInstalled(visionModel) {
            await pullModel(visionModel)
        }
        
        // Pull default reasoning model
        let reasoningModel = UserDefaults.standard.string(forKey: "ollamaReasoningModel") ?? "qwen3.5:4b"
        if !isModelInstalled(reasoningModel) {
            await pullModel(reasoningModel)
        }
        
        await MainActor.run {
            addLog("✅ Quick Setup complete!", type: .success)
        }
    }
    
    // MARK: - Helpers
    
    /// Check if a model is already installed (by matching name prefix).
    func isModelInstalled(_ modelId: String) -> Bool {
        installedModels.contains { model in
            model.name == modelId || model.name.hasPrefix(modelId.split(separator: ":").first.map(String.init) ?? modelId)
        }
    }
    
    /// Check if a model is currently being pulled.
    func isModelPulling(_ modelId: String) -> Bool {
        pullProgress[modelId] != nil
    }
    
    private func addLog(_ message: String, type: SetupLogEntry.LogType) {
        setupLog.append(SetupLogEntry(message: message, type: type, timestamp: Date()))
        // Keep last 50 entries
        if setupLog.count > 50 {
            setupLog.removeFirst(setupLog.count - 50)
        }
    }
    
    /// Run a shell command synchronously and return trimmed output.
    private func runShellSync(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        
        // Use login shell to get PATH
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    /// Run a shell command asynchronously and return output.
    private func runShellAsync(_ command: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                process.standardOutput = pipe
                process.standardError = pipe
                process.environment = ProcessInfo.processInfo.environment
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Types

struct InstalledModel: Identifiable {
    let name: String
    let size: Int64
    let modifiedAt: String?
    let parameterSize: String?
    let family: String?
    
    var id: String { name }
    
    var formattedSize: String {
        let gb = Double(size) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(size) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

struct PullProgress {
    let status: String
    let completed: Int64
    let total: Int64
    
    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
    
    var percentString: String {
        guard total > 0 else { return status }
        return "\(Int(fraction * 100))%"
    }
    
    var isDownloading: Bool {
        total > 0 && completed < total
    }
}

struct SetupLogEntry: Identifiable {
    let id = UUID()
    let message: String
    let type: LogType
    let timestamp: Date
    
    enum LogType {
        case info, success, warning, error
        
        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }
}
