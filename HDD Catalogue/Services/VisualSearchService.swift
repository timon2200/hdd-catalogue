import Foundation
import AppKit
import Vision

/// AI Visual Search service using Apple Vision (on-device) + Ollama (local LLM).
///
/// - **Visual tagging**: `VNClassifyImageRequest` — free, instant, offline
/// - **Find Similar**: `VNFeaturePrintObservation` — free, instant, offline
/// - **Natural language queries**: Ollama Qwen 3.5 — local, free, private
@Observable
final class VisualSearchService {
    private let ollamaBaseURL = "http://localhost:11434"
    
    var responseText: String = ""
    var currentStep: String = ""
    var status: AIStatus = .idle
    
    enum AIStatus: Equatable {
        case idle
        case sending
        case processing
        case parsing
        case done
        case error(String)
    }
    
    // Visual indexing progress (observable by views)
    var isVisualIndexing: Bool = false
    var visualIndexingCurrentProject: String = ""
    var visualIndexingProgress: Double = 0
    var visualIndexingTotal: Int = 0
    var visualIndexingCompleted: Int = 0
    var visualIndexingTagsFound: Int = 0
    
    // MARK: - Visual Indexing (Apple Vision — FREE, on-device)
    
    /// Index a project's visual content using Apple Vision on-device classification.
    /// Returns tags and a description — no network calls, instant, free.
    func indexProjectVisuals(thumbnailData: Data) async throws -> VisualIndexResult {
        guard let cgImage = cgImage(from: thumbnailData) else {
            throw VisualSearchError.invalidImage
        }
        
        let tags = try await classifyImage(cgImage)
        
        let topTags = tags.prefix(5).map(\.label)
        let description = topTags.isEmpty
            ? "Unclassified visual content"
            : topTags.joined(separator: ", ")
        
        return VisualIndexResult(
            tags: tags.map(\.label),
            description: description
        )
    }
    
    /// Classify an image using VNClassifyImageRequest.
    /// Returns labels sorted by confidence (≥ 15% confidence threshold).
    private func classifyImage(_ cgImage: CGImage) async throws -> [(label: String, confidence: Float)] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let results = observations
                    .filter { $0.confidence >= 0.15 }
                    .prefix(15)
                    .map { (label: $0.identifier.replacingOccurrences(of: "_", with: " "), confidence: $0.confidence) }
                
                continuation.resume(returning: Array(results))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Visual Search (local tag matching — FREE)
    
    /// Search projects by visual content using tag matching.
    /// Entirely local, no API calls.
    func visualSearch(query: String, projects: [Project]) -> [VisualSearchResult] {
        let queryTerms = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }
        
        guard !queryTerms.isEmpty else { return [] }
        
        var results: [VisualSearchResult] = []
        
        for project in projects where project.isVisuallyIndexed {
            let allSearchable = project.visualTags.map { $0.lowercased() }
                + [project.visualDescription.lowercased()]
            
            var matchCount = 0
            var matchedTerms: [String] = []
            
            for term in queryTerms {
                if allSearchable.contains(where: { $0.contains(term) }) {
                    matchCount += 1
                    matchedTerms.append(term)
                }
            }
            
            if matchCount > 0 {
                let relevance = Double(matchCount) / Double(queryTerms.count)
                results.append(VisualSearchResult(
                    projectId: project.id,
                    relevance: relevance,
                    matchedTags: matchedTerms,
                    reason: "Matched: \(matchedTerms.joined(separator: ", "))"
                ))
            }
        }
        
        return results.sorted { $0.relevance > $1.relevance }
    }
    
    // MARK: - Natural Language Query (Ollama local — no API key, fully private)
    
    /// Process a natural language query using local Ollama to interpret it against project metadata.
    /// Only sends text metadata — no images, fully local.
    func naturalLanguageSearch(query: String, projects: [Project]) async throws -> [VisualSearchResult] {
        await MainActor.run {
            currentStep = "Interpreting query…"
            responseText = ""
            status = .sending
        }
        
        let projectSummaries = projects.prefix(500).map { project -> String in
            let dateStr: String
            if let date = project.projectDate {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                dateStr = f.string(from: date)
            } else {
                dateStr = "unknown"
            }
            let nles = project.detectedNLEs.joined(separator: ",")
            let tags = project.visualTags.prefix(5).joined(separator: ",")
            let client = project.client?.name ?? "none"
            let status = project.statusRaw
            return "\(project.id.uuidString.prefix(8))|\(project.displayName)|\(project.projectType)|\(project.formattedSize)|\(dateStr)|\(nles)|\(client)|\(status)|\(tags)"
        }.joined(separator: "\n")
        
        let prompt = """
        Search a video editor's project catalogue for: "\(query)"
        Today: \(todayString()). Format: id|name|type|size|date|nles|client|status|tags
        
        \(projectSummaries)
        
        Return ONLY a JSON array of matches (top 20, or [] if none), no other text:
        [{"id": "first-8-chars-of-uuid", "relevance": 0.95, "reason": "Brief explanation"}]
        """
        
        let text = try await callOllamaTextAPI(prompt: prompt)
        
        await MainActor.run {
            currentStep = "Processing results…"
            self.status = .parsing
        }
        
        return try parseNLSearchResults(text, allProjects: projects)
    }
    
    // MARK: - Find Similar (Apple Vision Feature Print — FREE, on-device)
    
    /// Find visually similar projects using Apple Vision feature print comparison.
    /// Entirely on-device, no API calls.
    func findSimilar(sourceProject: Project, allProjects: [Project]) async throws -> [SimilarResult] {
        guard let sourceData = sourceProject.thumbnailData,
              let sourceImage = cgImage(from: sourceData) else {
            throw VisualSearchError.invalidImage
        }
        
        await MainActor.run {
            currentStep = "Generating feature print…"
            responseText = ""
            status = .processing
        }
        
        let sourceFeaturePrint = try await generateFeaturePrint(sourceImage)
        
        let candidates = allProjects.filter {
            $0.id != sourceProject.id && $0.thumbnailData != nil
        }
        
        guard !candidates.isEmpty else {
            await MainActor.run { status = .done }
            return []
        }
        
        await MainActor.run {
            currentStep = "Comparing \(candidates.count) projects…"
            status = .processing
        }
        
        var results: [SimilarResult] = []
        
        for candidate in candidates {
            guard let candidateData = candidate.thumbnailData,
                  let candidateImage = cgImage(from: candidateData) else { continue }
            
            do {
                let candidateFeaturePrint = try await generateFeaturePrint(candidateImage)
                var distance: Float = 0
                try sourceFeaturePrint.computeDistance(&distance, to: candidateFeaturePrint)
                
                // Convert distance to similarity (lower distance = more similar)
                let similarity = max(0, 1.0 - Double(distance) / 60.0)
                
                if similarity > 0.2 {
                    let sharedTags = Set(sourceProject.visualTags).intersection(Set(candidate.visualTags))
                    let reason: String
                    if !sharedTags.isEmpty {
                        reason = "Similar: \(sharedTags.prefix(4).joined(separator: ", "))"
                    } else {
                        reason = "Visually similar content"
                    }
                    
                    results.append(SimilarResult(
                        projectId: candidate.id,
                        similarity: similarity,
                        reason: reason
                    ))
                }
            } catch {
                continue
            }
        }
        
        await MainActor.run { status = .done }
        
        return Array(results.sorted { $0.similarity > $1.similarity }.prefix(10))
    }
    
    /// Generate a feature print for an image using Apple Vision.
    private func generateFeaturePrint(_ cgImage: CGImage) async throws -> VNFeaturePrintObservation {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(throwing: VisualSearchError.featurePrintFailed)
                    return
                }
                
                continuation.resume(returning: observation)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Ollama Text API (for NL queries)
    
    private func callOllamaTextAPI(prompt: String) async throws -> String {
        let url = URL(string: "\(ollamaBaseURL)/api/chat")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let modelName = UserDefaults.standard.string(forKey: "ollamaReasoningModel") ?? "qwen3.5:4b"
        
        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "stream": false,
            "think": false,
            "format": "json",
            "options": [
                "temperature": 0.2,
                "num_predict": 4096
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        await MainActor.run { status = .processing }
        
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
            status = .processing
        }
        
        return text
    }
    
    // MARK: - Parsing
    
    private func parseNLSearchResults(_ text: String, allProjects: [Project]) throws -> [VisualSearchResult] {
        let cleaned = cleanJSONArrayResponse(text)
        guard let data = cleaned.data(using: .utf8) else { return [] }
        
        struct RawResult: Codable {
            let id: String
            let relevance: Double
            let reason: String
        }
        
        let rawResults: [RawResult]
        do {
            rawResults = try JSONDecoder().decode([RawResult].self, from: data)
        } catch {
            throw GeminiError.parseError(detail: "NL search JSON decode failed: \(error.localizedDescription)")
        }
        
        return rawResults.compactMap { raw in
            guard let project = allProjects.first(where: {
                $0.id.uuidString.prefix(8).lowercased() == raw.id.lowercased()
            }) else { return nil }
            
            return VisualSearchResult(
                projectId: project.id,
                relevance: raw.relevance,
                matchedTags: [],
                reason: raw.reason
            )
        }
    }
    
    // MARK: - Helpers
    
    private func cgImage(from data: Data) -> CGImage? {
        guard let nsImage = NSImage(data: data),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.cgImage
    }
    
    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    
    private func cleanJSONArrayResponse(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        else if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let start = cleaned.firstIndex(of: "["),
           let end = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[start...end])
        }
        
        if let _ = try? JSONSerialization.jsonObject(with: Data(cleaned.utf8)) {
            return cleaned
        }
        
        if let lastBrace = cleaned.lastIndex(of: "}") {
            var truncated = String(cleaned[cleaned.startIndex...lastBrace])
            truncated = truncated.trimmingCharacters(in: .whitespacesAndNewlines)
            if truncated.hasSuffix(",") {
                truncated = String(truncated.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !truncated.hasSuffix("]") { truncated += "]" }
            return truncated
        }
        
        return cleaned
    }
}

// MARK: - Errors

enum VisualSearchError: LocalizedError {
    case invalidImage
    case featurePrintFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process thumbnail image"
        case .featurePrintFailed: return "Failed to generate image feature print"
        }
    }
}

// MARK: - Response Models

struct VisualIndexResult: Codable {
    let tags: [String]
    let description: String
}

struct VisualSearchResult: Identifiable {
    let projectId: UUID
    let relevance: Double
    let matchedTags: [String]
    let reason: String
    
    var id: UUID { projectId }
}

struct SimilarResult: Identifiable {
    let projectId: UUID
    let similarity: Double
    let reason: String
    
    var id: UUID { projectId }
}
