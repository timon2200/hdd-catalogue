import Foundation
import SwiftData

/// AI service for project categorization and duplicate detection.
/// Uses local Ollama (Qwen 3.5) — no API key required, fully on-device, free.
@Observable
final class GeminiService {
    private let ollamaBaseURL = "http://localhost:11434"
    
    /// The final response text from the model.
    var responseText: String = ""
    /// Current step label.
    var currentStep: String = ""
    /// Status for the UI.
    var status: AIStatus = .idle
    
    enum AIStatus: Equatable {
        case idle
        case sending
        case processing
        case parsing
        case done
    }
    
    /// Which Ollama model to use for text reasoning (categorization, duplicates).
    /// Uses the bigger model for better accuracy — separate from the vision model.
    private var modelName: String {
        UserDefaults.standard.string(forKey: "ollamaReasoningModel") ?? "qwen3.5:4b"
    }
    
    /// Categorize projects — identify clients, project types, and summaries.
    func categorizeProjects(_ projects: [Project], existingClients: [Client]) async throws -> [ProjectCategorization] {
        
        await MainActor.run {
            currentStep = "Categorizing \(projects.count) projects…"
            responseText = ""
            status = .sending
        }
        
        // Build folder info for the prompt
        let folderDescriptions = projects.map { project in
            let modified = project.dateModified.map { 
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f.string(from: $0)
            } ?? "unknown"
            return "- \(project.folderName) (size: \(project.formattedSize), modified: \(modified), files: \(project.fileCount))"
        }.joined(separator: "\n")
        
        let existingClientNames = existingClients.map(\.name).joined(separator: ", ")
        let clientContext = existingClientNames.isEmpty ? "" : "\nExisting clients: \(existingClientNames). Match to these first.\n"
        
        let prompt = """
        Analyze these project folders from a creative professional's external drive.\(clientContext)
        For each folder, identify the client, project type (Web Design, Video Edit, Photography, 3D/Motion, Development, Branding, Music/Audio, Documentation, or Other), and a 1-line summary.
        
        Return ONLY a JSON array, no other text:
        [{"folderName": "exact_folder_name", "clientName": "Client Name", "projectType": "Type", "summary": "Brief description", "confidence": 0.95}]
        
        Folders:
        \(folderDescriptions)
        """
        
        let text = try await callOllamaAPI(prompt: prompt, jsonMode: true)
        
        await MainActor.run {
            currentStep = "Parsing categorization results…"
            status = .parsing
        }
        
        return try parseCategorizationResponse(text)
    }
    
    /// Categorize a single project with rich camera/file context.
    /// Called one-by-one so the UI can show per-project progress.
    func categorizeProjectWithContext(
        _ project: Project,
        index: Int,
        total: Int,
        existingClients: [Client]
    ) async throws -> ProjectCategorization? {
        
        await MainActor.run {
            currentStep = "Analyzing \(index)/\(total): \(project.displayName)…"
            status = .sending
        }
        
        guard let drivePath = project.drive?.volumePath else { return nil }
        let projectPath = drivePath + "/" + project.folderName
        
        // Scan folder structure for camera context
        let cameraContext = scanProjectForCameraContext(projectPath: projectPath)
        
        let modified = project.dateModified.map {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: $0)
        } ?? "unknown"
        
        let existingClientNames = existingClients.map(\.name).joined(separator: ", ")
        let clientContext = existingClientNames.isEmpty ? "" : "\nExisting clients: \(existingClientNames). Match to these first.\n"
        
        let prompt = """
        You are a creative project analyst. Analyze this single project folder from a professional's external drive.\(clientContext)
        
        Project folder: \(project.folderName)
        Size: \(project.formattedSize)
        Modified: \(modified)
        File count: \(project.fileCount)
        
        \(cameraContext)
        
        Based on ALL of this context, identify:
        1. The client name (from the folder name, typically the brand or person name)
        2. Project type: Video Edit, Photography, 3D/Motion, Web Design, Development, Branding, Music/Audio, Documentation, or Other
        3. A detailed 1-2 line summary that mentions the cameras used, footage format, and what the project likely contains
        
        Return ONLY a JSON object (no markdown):
        {"folderName": "\(project.folderName)", "clientName": "Client Name", "projectType": "Type", "summary": "Detailed description mentioning cameras and footage", "confidence": 0.9}
        """
        
        await MainActor.run {
            currentStep = "Waiting for AI: \(project.displayName)…"
            status = .processing
        }
        
        let text: String
        do {
            text = try await callOllamaAPI(prompt: prompt, jsonMode: true)
        } catch {
            // If individual project fails, log and continue
            print("AI categorization failed for \(project.folderName): \(error)")
            return nil
        }
        
        await MainActor.run {
            currentStep = "Parsing: \(project.displayName)…"
            status = .parsing
        }
        
        // Parse single object response
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[start...end])
            }
        }
        // If it's wrapped in an array, unwrap
        if cleaned.hasPrefix("[") {
            if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[start...end])
            }
        }
        
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(ProjectCategorization.self, from: data) else {
            return nil
        }
        
        return result
    }
    
    /// Scan a project directory for camera context information
    private func scanProjectForCameraContext(projectPath: String) -> String {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: projectPath)
        
        guard let topContents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return "Folder structure: Unable to read"
        }
        
        var context = "Folder structure:\n"
        var cameras: [String] = []
        var videoFormats: Set<String> = []
        var imageFormats: Set<String> = []
        var hasAudio = false
        var hasProjectFiles = false
        
        // Known NLE / design project file extensions
        let nleExtensions: Set<String> = ["prproj", "aep", "drp", "fcpbundle", "psd", "ai", "indd", "blend", "c4d", "ma", "mb"]
        let videoExtensions: Set<String> = ["mp4", "mov", "mxf", "avi", "mkv", "m4v", "braw", "r3d"]
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "cr2", "cr3", "arw", "nef", "dng", "raf", "heic"]
        let audioExtensions: Set<String> = ["wav", "mp3", "aiff", "flac", "aac", "m4a"]
        
        // Camera name patterns from folder names
        let cameraPatterns: [(pattern: String, camera: String)] = [
            ("mavic", "DJI Mavic"),
            ("mini", "DJI Mini"),
            ("air", "DJI Air"),
            ("dji", "DJI Drone"),
            ("a7iv", "Sony A7 IV"), ("a7m4", "Sony A7 IV"), ("a7 iv", "Sony A7 IV"),
            ("a7v", "Sony A7V"), ("a7m5", "Sony A7V"),
            ("a7siii", "Sony A7S III"), ("a7s3", "Sony A7S III"),
            ("a7iii", "Sony A7 III"), ("a7m3", "Sony A7 III"),
            ("zv-e1", "Sony ZV-E1"), ("zve1", "Sony ZV-E1"),
            ("fx3", "Sony FX3"), ("fx6", "Sony FX6"), ("fx30", "Sony FX30"),
            ("fpv", "GoPro FPV"),
            ("gopro", "GoPro"),
            ("sony", "Sony Camera"),
            ("canon", "Canon Camera"),
            ("bmpcc", "Blackmagic Pocket"),
            ("r5", "Canon EOS R5"), ("r6", "Canon EOS R6"),
        ]
        
        func scanFolder(_ folderURL: URL, depth: Int) {
            guard depth < 3 else { return }
            let folderName = folderURL.lastPathComponent.lowercased()
            
            // Check folder name for camera
            for (pattern, camera) in cameraPatterns {
                if folderName.contains(pattern) && !cameras.contains(camera) {
                    cameras.append(camera)
                    break
                }
            }
            
            guard let contents = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            
            for item in contents {
                let ext = item.pathExtension.lowercased()
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                
                if isDir {
                    scanFolder(item, depth: depth + 1)
                } else {
                    if videoExtensions.contains(ext) { videoFormats.insert(ext.uppercased()) }
                    if imageExtensions.contains(ext) { imageFormats.insert(ext.uppercased()) }
                    if audioExtensions.contains(ext) { hasAudio = true }
                    if nleExtensions.contains(ext) { hasProjectFiles = true }
                    
                    // Check file name patterns for camera
                    let fileName = item.lastPathComponent.uppercased()
                    if fileName.hasPrefix("DJI_") && !cameras.contains(where: { $0.contains("DJI") }) {
                        cameras.append("DJI Drone")
                    }
                    if fileName.range(of: #"^C\d{4,5}\."#, options: .regularExpression) != nil && !cameras.contains(where: { $0.contains("Sony") }) {
                        cameras.append("Sony Camera")
                    }
                    if fileName.range(of: #"^(GX|GOPR|GP)\d{4,8}\."#, options: .regularExpression) != nil && !cameras.contains(where: { $0.contains("GoPro") }) {
                        cameras.append("GoPro")
                    }
                }
            }
        }
        
        // List top-level folders
        let topFolders = topContents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
        let topFiles = topContents.filter { !((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
        
        context += "Top-level folders: \(topFolders.map(\.lastPathComponent).joined(separator: ", "))\n"
        if !topFiles.isEmpty {
            let sampleFiles = topFiles.prefix(10).map(\.lastPathComponent).joined(separator: ", ")
            context += "Top-level files: \(sampleFiles)\n"
        }
        
        // Scan all folders for cameras
        for folder in topFolders {
            scanFolder(folder, depth: 0)
        }
        // Also check top-level files
        for file in topFiles {
            let ext = file.pathExtension.lowercased()
            if videoExtensions.contains(ext) { videoFormats.insert(ext.uppercased()) }
            if imageExtensions.contains(ext) { imageFormats.insert(ext.uppercased()) }
            if audioExtensions.contains(ext) { hasAudio = true }
            if nleExtensions.contains(ext) { hasProjectFiles = true }
        }
        
        if !cameras.isEmpty {
            context += "Cameras detected: \(cameras.joined(separator: ", "))\n"
        }
        if !videoFormats.isEmpty {
            context += "Video formats: \(videoFormats.sorted().joined(separator: ", "))\n"
        }
        if !imageFormats.isEmpty {
            context += "Image formats: \(imageFormats.sorted().joined(separator: ", "))\n"
        }
        if hasAudio {
            context += "Contains audio files\n"
        }
        if hasProjectFiles {
            let projectExts = topContents.map { $0.pathExtension.lowercased() }.filter { nleExtensions.contains($0) }
            context += "Project files: \(Set(projectExts).joined(separator: ", "))\n"
        }
        
        return context
    }
    
    /// Detect duplicate projects across multiple drives.
    func detectDuplicates(allProjects: [Project]) async throws -> [DuplicateDetection] {
        guard allProjects.count > 1 else { return [] }
        
        await MainActor.run {
            currentStep = "Scanning for duplicates across \(allProjects.count) projects…"
            responseText = ""
            status = .sending
        }
        
        let projectDescriptions = allProjects.compactMap { project -> String? in
            guard let driveName = project.drive?.name else { return nil }
            let modified = project.dateModified.map {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f.string(from: $0)
            } ?? "unknown"
            return "- \(driveName):/\(project.folderName) (size: \(project.formattedSize), modified: \(modified), files: \(project.fileCount))"
        }.joined(separator: "\n")
        
        let prompt = """
        Identify groups of folders that are the SAME PROJECT on different drives or in different states (versions, backups, different sizes/dates).
        
        Return ONLY a JSON array (empty [] if none), no other text:
        [{"groupName": "Group name", "members": ["Drive:/Folder"], "latestVersion": "Drive:/Folder", "suggestedAction": "Explanation"}]
        
        Projects:
        \(projectDescriptions)
        """
        
        let text = try await callOllamaAPI(prompt: prompt, jsonMode: true)
        
        await MainActor.run {
            currentStep = "Parsing duplicate detection results…"
            status = .parsing
        }
        
        return try parseDuplicateResponse(text)
    }
    
    // MARK: - Ollama API Communication
    
    func callOllamaAPI(prompt: String, jsonMode: Bool = false) async throws -> String {
        let url = URL(string: "\(ollamaBaseURL)/api/chat")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        var body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "stream": false,
            "think": false,
            "options": [
                "temperature": 0.2,
                "num_predict": 4096
            ]
        ]
        
        if jsonMode {
            body["format"] = "json"
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        await MainActor.run {
            status = .processing
            currentStep = "Waiting for Ollama (\(modelName))…"
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any] else {
            throw GeminiError.invalidResponse
        }
        
        // Qwen 3.5 may put content in "thinking" if think mode leaks through
        let text = (message["content"] as? String).flatMap({ $0.isEmpty ? nil : $0 })
                ?? (message["thinking"] as? String)
                ?? ""
        
        await MainActor.run {
            responseText = text
        }
        
        guard !text.isEmpty else {
            throw GeminiError.invalidResponse
        }
        
        return text
    }
    
    // MARK: - Response Parsing
    
    private func parseCategorizationResponse(_ text: String) throws -> [ProjectCategorization] {
        let cleaned = cleanJSONResponse(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiError.parseError(detail: "Could not convert response to data")
        }
        
        do {
            return try JSONDecoder().decode([ProjectCategorization].self, from: data)
        } catch {
            throw GeminiError.parseError(detail: "JSON decode failed: \(error.localizedDescription)\n\nRaw response:\n\(text.prefix(500))")
        }
    }
    
    private func parseDuplicateResponse(_ text: String) throws -> [DuplicateDetection] {
        let cleaned = cleanJSONResponse(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiError.parseError(detail: "Could not convert response to data")
        }
        
        do {
            return try JSONDecoder().decode([DuplicateDetection].self, from: data)
        } catch {
            throw GeminiError.parseError(detail: "JSON decode failed: \(error.localizedDescription)\n\nRaw response:\n\(text.prefix(500))")
        }
    }
    
    /// Strips markdown code fences and extracts the JSON array.
    private func cleanJSONResponse(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code block markers (safety net)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find the JSON array start
        guard let startIndex = cleaned.firstIndex(of: "[") else {
            return cleaned
        }
        
        if let endIndex = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[startIndex...endIndex])
        } else {
            cleaned = String(cleaned[startIndex...])
        }
        
        // Try parsing as-is first
        if let _ = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8)) {
            return cleaned
        }
        
        // Handle truncated JSON: remove the last incomplete object and close the array
        if let lastBrace = cleaned.lastIndex(of: "}") {
            var truncated = String(cleaned[cleaned.startIndex...lastBrace])
            truncated = truncated.trimmingCharacters(in: .whitespacesAndNewlines)
            if truncated.hasSuffix(",") {
                truncated = String(truncated.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !truncated.hasSuffix("]") {
                truncated += "]"
            }
            return truncated
        }
        
        return cleaned
    }
}

// MARK: - Response Models

struct ProjectCategorization: Codable {
    let folderName: String
    let clientName: String
    let projectType: String
    let summary: String
    let confidence: Float
}

struct DuplicateDetection: Codable {
    let groupName: String
    let members: [String]
    let latestVersion: String
    let suggestedAction: String
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case parseError(detail: String)
    case apiError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Ollama is not running. Please start Ollama and ensure a model is pulled."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Received invalid response from Ollama. Make sure the model is available."
        case .parseError(let detail):
            return "Failed to parse AI response: \(detail)"
        case .apiError(let code, let message):
            return "Ollama error (\(code)): \(message)"
        }
    }
}
