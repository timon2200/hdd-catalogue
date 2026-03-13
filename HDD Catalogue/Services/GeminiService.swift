import Foundation
import SwiftData

/// Communicates with Google Gemini API for project categorization and duplicate detection.
final class GeminiService {
    private let apiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
    
    /// Categorize projects — identify clients, project types, and summaries.
    func categorizeProjects(_ projects: [Project], existingClients: [Client]) async throws -> [ProjectCategorization] {
        let apiKey = KeychainHelper.getAPIKey()
        guard !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
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
        let clientContext = existingClientNames.isEmpty ? "" : "\nExisting known clients: \(existingClientNames)\nTry to match projects to these clients first before creating new ones."
        
        let prompt = """
        You are analyzing project folders from an external hard drive belonging to a creative professional.
        Given these folder names and metadata, identify:
        1. Which folders likely belong to the same client (look for naming patterns, prefixes, etc.)
        2. What type of project each folder contains (Web Design, Video Edit, Photography, 3D/Motion, Development, Branding, Music/Audio, Documentation, or Other)
        3. A brief 1-line summary of what the project likely contains
        \(clientContext)
        
        Return ONLY a valid JSON array, no markdown formatting, no code blocks:
        [{"folderName": "exact_folder_name", "clientName": "Client Name", "projectType": "Web Design", "summary": "Brief description", "confidence": 0.95}]
        
        Folders to analyze:
        \(folderDescriptions)
        """
        
        let responseText = try await callGeminiAPI(prompt: prompt, apiKey: apiKey)
        return try parseCategorizationResponse(responseText)
    }
    
    /// Detect duplicate projects across multiple drives.
    func detectDuplicates(allProjects: [Project]) async throws -> [DuplicateDetection] {
        let apiKey = KeychainHelper.getAPIKey()
        guard !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }
        
        guard allProjects.count > 1 else { return [] }
        
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
        Here are ALL catalogued project folders across multiple external drives.
        Identify groups of folders that appear to be the SAME PROJECT but on different drives
        or in different states (different sizes, different dates). Look for:
        - Same or very similar names (e.g., "ProjectX_v2" and "ProjectX_Final")
        - Same client prefix with version indicators
        - Backup copies
        
        For each group, determine which is the latest/most complete version based on size and date.
        
        Return ONLY a valid JSON array, no markdown, no code blocks. If no duplicates found, return []:
        [{"groupName": "Human-readable group name", "members": ["DriveName:/FolderName"], "latestVersion": "DriveName:/FolderName", "suggestedAction": "Explain why one is likely the latest version and what the user should do"}]
        
        Projects across all drives:
        \(projectDescriptions)
        """
        
        let responseText = try await callGeminiAPI(prompt: prompt, apiKey: apiKey)
        return try parseDuplicateResponse(responseText)
    }
    
    // MARK: - API Communication
    
    private func callGeminiAPI(prompt: String, apiKey: String) async throws -> String {
        let urlString = "\(apiBaseURL)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 8192
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        // Parse Gemini response structure
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.invalidResponse
        }
        
        return text
    }
    
    // MARK: - Response Parsing
    
    private func parseCategorizationResponse(_ text: String) throws -> [ProjectCategorization] {
        let cleaned = cleanJSONResponse(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiError.parseError
        }
        
        return try JSONDecoder().decode([ProjectCategorization].self, from: data)
    }
    
    private func parseDuplicateResponse(_ text: String) throws -> [DuplicateDetection] {
        let cleaned = cleanJSONResponse(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiError.parseError
        }
        
        return try JSONDecoder().decode([DuplicateDetection].self, from: data)
    }
    
    /// Strips markdown code fences and extracts the JSON array.
    private func cleanJSONResponse(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code block markers
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find the JSON array
        if let startIndex = cleaned.firstIndex(of: "["),
           let endIndex = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[startIndex...endIndex])
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
    case parseError
    case apiError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Gemini API key configured. Please add your API key in Settings."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Received invalid response from Gemini API."
        case .parseError:
            return "Failed to parse AI response. Please try again."
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        }
    }
}
