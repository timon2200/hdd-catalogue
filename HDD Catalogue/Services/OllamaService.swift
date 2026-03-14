import Foundation
import AppKit

/// Local Ollama API service for on-device image description.
/// Connects to Ollama running at localhost:11434.
/// Falls back gracefully if Ollama is not installed or running.
@Observable
final class OllamaService {
    
    // MARK: - Observable State
    
    var isAvailable: Bool = false
    var currentModel: String = "qwen3.5:0.8b"
    
    /// Live progress — observable by views
    var currentFile: String = ""
    var currentDescription: String = ""
    var descriptionsGenerated: Int = 0
    var descriptionsFailed: Int = 0
    
    // MARK: - Configuration
    
    private let baseURL = "http://localhost:11434"
    private let timeoutSeconds: TimeInterval = 60
    
    /// Supported models for image description, ordered by speed.
    static let supportedModels = [
        OllamaModel(id: "qwen3.5:0.8b", name: "Qwen 3.5 0.8B", size: "1 GB", description: "Fastest, great for bulk indexing"),
        OllamaModel(id: "qwen3.5:2b", name: "Qwen 3.5 2B", size: "2.7 GB", description: "Good balance of speed & quality"),
        OllamaModel(id: "qwen3.5:4b", name: "Qwen 3.5 4B", size: "3.4 GB", description: "Rich descriptions"),
        OllamaModel(id: "moondream", name: "Moondream 2", size: "1.7 GB", description: "Fast, basic captions"),
        OllamaModel(id: "llava:7b", name: "LLaVA 7B", size: "7 GB", description: "Good descriptions"),
    ]
    
    // MARK: - Connection Check
    
    /// Check if Ollama is running and the selected model is available.
    func checkAvailability() async {
        do {
            let url = URL(string: "\(baseURL)/api/tags")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run { isAvailable = false }
                return
            }
            
            // Check if our model is in the available models
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["name"] as? String }
                // Match model name flexibly (e.g. "qwen3.5:0.8b" matches "qwen3.5:0.8b", "qwen3.5:0.8b-fp16")
                let modelBase = currentModel.split(separator: ":").first.map(String.init) ?? currentModel
                let available = modelNames.contains(where: { $0.contains(modelBase) })
                await MainActor.run { isAvailable = available }
            } else {
                await MainActor.run { isAvailable = true } // API responded, assume OK
            }
        } catch {
            await MainActor.run { isAvailable = false }
        }
    }
    
    // MARK: - Context-Aware Description (Enhanced)
    
    /// Generate a rich description using multiple images and contextual metadata.
    /// Sends up to 4 images in a single chat request with a context-aware prompt.
    /// Falls back to the basic method if context is nil.
    func describeWithContext(
        images: [Data],
        context: DescriptionContext,
        filename: String? = nil
    ) async -> ImageDescription? {
        guard isAvailable, !images.isEmpty else { return nil }
        
        // Update progress
        if let name = filename {
            await MainActor.run { currentFile = name }
        }
        
        // Cap at 4 images (Ollama/Qwen limit)
        let imagesToSend = Array(images.prefix(4))
        let base64Images = imagesToSend.map { $0.base64EncodedString() }
        let prompt = context.buildPrompt(imageCount: imagesToSend.count)
        
        let payload: [String: Any] = [
            "model": currentModel,
            "messages": [
                [
                    "role": "user",
                    "content": prompt,
                    "images": base64Images
                ]
            ],
            "stream": false,
            "think": false,
            "options": [
                "temperature": 0.3,
                "num_predict": 150  // Terse 1-2 sentence descriptions
            ]
        ]
        
        do {
            let url = URL(string: "\(baseURL)/api/chat")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.timeoutInterval = timeoutSeconds
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run { descriptionsFailed += 1 }
                return nil
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any] else {
                await MainActor.run { descriptionsFailed += 1 }
                return nil
            }
            
            // Qwen 3.5 may put content in "thinking" if think mode leaks
            let responseText = (message["content"] as? String).flatMap({ $0.isEmpty ? nil : $0 })
                    ?? (message["thinking"] as? String)
                    ?? ""
            
            let description = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty else {
                await MainActor.run { descriptionsFailed += 1 }
                return nil
            }
            
            await MainActor.run {
                currentDescription = description
                descriptionsGenerated += 1
            }
            
            return ImageDescription(description: description, model: currentModel)
        } catch {
            await MainActor.run { descriptionsFailed += 1 }
            return nil
        }
    }
    
    /// Convert a CGImage to compressed JPEG Data, resized to maxDim for speed.
    func cgImageToJPEG(_ cgImage: CGImage, maxDim: CGFloat = 512) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let scale = min(maxDim / CGFloat(cgImage.width), maxDim / CGFloat(cgImage.height), 1.0)
        let newSize = NSSize(
            width: CGFloat(cgImage.width) * scale,
            height: CGFloat(cgImage.height) * scale
        )
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return jpegData
    }
    
    // MARK: - Basic Image Description (Legacy — no context)
    
    /// Generate a description for an image using the local Ollama model.
    /// Uses /api/chat with images in message content (compatible with Qwen 3.5, LLaVA, etc.)
    /// Returns nil if Ollama is not available or the request fails.
    func describeImage(_ imageData: Data, prompt: String? = nil, filename: String? = nil) async -> ImageDescription? {
        guard isAvailable else { return nil }
        
        // Update progress
        if let name = filename {
            await MainActor.run { currentFile = name }
        }
        
        let base64Image = imageData.base64EncodedString()
        let descPrompt = prompt ?? "Describe this image concisely in one sentence. Focus on the main subject, setting, and mood. Be specific about what you see."
        
        // Use /api/chat endpoint — the universal format for all multimodal models
        let payload: [String: Any] = [
            "model": currentModel,
            "messages": [
                [
                    "role": "user",
                    "content": descPrompt,
                    "images": [base64Image]
                ]
            ],
            "stream": false,
            "think": false,
            "options": [
                "temperature": 0.3,
                "num_predict": 150  // Keep descriptions concise
            ]
        ]
        
        do {
            let url = URL(string: "\(baseURL)/api/chat")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.timeoutInterval = timeoutSeconds
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run { descriptionsFailed += 1 }
                return nil
            }
            
            // Parse chat response format: {"message": {"content": "..."}}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any] else {
                await MainActor.run { descriptionsFailed += 1 }
                return nil
            }
            
            // Qwen 3.5 may put content in "thinking" if think mode leaks
            let responseText = (message["content"] as? String).flatMap({ $0.isEmpty ? nil : $0 })
                    ?? (message["thinking"] as? String)
                    ?? ""
            
            let description = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty else {
                await MainActor.run { descriptionsFailed += 1 }
                return nil
            }
            
            await MainActor.run {
                currentDescription = description
                descriptionsGenerated += 1
            }
            
            return ImageDescription(
                description: description,
                model: currentModel
            )
        } catch {
            await MainActor.run { descriptionsFailed += 1 }
            return nil
        }
    }
    
    /// Generate a description from a CGImage (converts to JPEG data first).
    func describeImage(_ cgImage: CGImage, prompt: String? = nil, filename: String? = nil) async -> ImageDescription? {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        // Resize to max 512px for speed
        let maxDim: CGFloat = 512
        let scale = min(maxDim / CGFloat(cgImage.width), maxDim / CGFloat(cgImage.height), 1.0)
        let newSize = NSSize(
            width: CGFloat(cgImage.width) * scale,
            height: CGFloat(cgImage.height) * scale
        )
        
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        
        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        
        return await describeImage(jpegData, prompt: prompt, filename: filename)
    }
    
    /// Generate a description from a file URL.
    func describeImageFile(at url: URL, prompt: String? = nil) async -> ImageDescription? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        // Resize for speed — load via NSImage, resize to 512px max
        guard let nsImage = NSImage(data: data) else { return nil }
        let size = nsImage.size
        let maxDim: CGFloat = 512
        let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        
        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        
        return await describeImage(jpegData, prompt: prompt, filename: url.lastPathComponent)
    }
    
    /// Reset progress counters.
    func resetProgress() {
        currentFile = ""
        currentDescription = ""
        descriptionsGenerated = 0
        descriptionsFailed = 0
    }
}

// MARK: - Types

struct OllamaModel: Identifiable {
    let id: String
    let name: String
    let size: String
    let description: String
}

struct ImageDescription {
    let description: String
    let model: String
}

// MARK: - Description Context

/// Bundles all available metadata to build a context-aware prompt for Qwen.
struct DescriptionContext {
    // Project-level context
    var projectName: String?
    var projectType: String?       // "Video Edit", "Photography", etc.
    var clientName: String?
    var detectedNLEs: [String]?
    var cameraSources: [String]?
    
    // File-level context
    var folderPath: String?        // Relative path within project
    var fileType: MediaFileType = .other
    var duration: Double?          // Seconds (for videos)
    var resolution: String?
    var codec: String?
    var frameRate: Double?
    var colorSpace: String?
    var cameraModel: String?       // From EXIF
    var iso: Int?
    var shutterSpeed: String?
    var lens: String?
    
    // Pre-computed tags (from Apple Vision)
    var visionTags: [String]?
    var detectedText: String?
    var faceCount: Int?
    
    // Motion analysis (computed from frame comparison)
    var motionHint: String?  // e.g. "significant camera movement detected" or "camera appears static"
    
    /// Build a context-aware prompt for the given number of images.
    func buildPrompt(imageCount: Int) -> String {
        var parts: [String] = []
        
        // Compact context line
        var ctx: [String] = []
        if let name = projectName { ctx.append(name) }
        if let type = projectType, type != "Unknown" { ctx.append(type) }
        if let client = clientName { ctx.append("for \(client)") }
        if !ctx.isEmpty { parts.append("Project: \(ctx.joined(separator: " — "))") }
        
        // Compact metadata line
        var meta: [String] = []
        if let path = folderPath { meta.append(path) }
        if let dur = duration {
            let mins = Int(dur) / 60; let secs = Int(dur) % 60
            meta.append(dur >= 3600 ? String(format: "%d:%02d:%02d", Int(dur)/3600, mins%60, secs) : String(format: "%d:%02d", mins, secs))
        }
        if let res = resolution { meta.append(res) }
        if let c = codec { meta.append(c) }
        if let fps = frameRate { meta.append("\(String(format: "%.2g", fps))fps") }
        if let cs = colorSpace { meta.append(cs) }
        if let cam = cameraModel { meta.append(cam) }
        if !meta.isEmpty { parts.append(meta.joined(separator: " · ")) }
        
        // Vision tags
        if let tags = visionTags, !tags.isEmpty {
            parts.append("Tags: \(tags.joined(separator: ", "))")
        }
        if let faces = faceCount, faces > 0 { parts.append("\(faces) face\(faces == 1 ? "" : "s")") }
        
        // Task instruction — terse, no fluff
        if fileType == .video {
            if imageCount > 1 {
                parts.append("Image 1 = first second of clip. Image 2 = last second of clip.")
            }
            if let hint = motionHint {
                parts.append("Motion analysis: \(hint).")
            }
            parts.append("Describe this clip: the action happening, camera movement, setting, mood. Write 1-3 plain sentences for search. No headers, no bullets, no preamble.")
        } else if fileType == .image {
            parts.append("Describe this image: subject, setting, lighting, mood. Write 1-3 plain sentences for search. No headers, no bullets, no preamble.")
        } else {
            parts.append("Describe what you see in 1-3 plain sentences. No headers, no bullets, no preamble.")
        }
        
        return parts.joined(separator: "\n")
    }
}
