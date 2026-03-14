import SwiftUI

/// Floating panel that shows the AI model's progress during analysis.
/// Optimized for gemini-2.0-flash-lite — fast responses, no thinking stream.
struct AIThinkingPanel: View {
    let geminiService: GeminiService
    
    @State private var isExpanded = true
    @State private var elapsedSeconds = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse)
                
                Text("AI Analysis")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Elapsed time
                Text(formatElapsed(elapsedSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            if isExpanded {
                Divider()
                
                // Status bar
                HStack(spacing: 6) {
                    statusIcon
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.3))
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            // Response section
                            if !geminiService.responseText.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Response", systemImage: "text.justify.left")
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                    
                                    Text(geminiService.responseText.prefix(1200))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(14)
                    }
                    .onChange(of: geminiService.responseText) {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .onAppear {
            elapsedSeconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                elapsedSeconds += 1
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch geminiService.status {
        case .idle:
            Image(systemName: "circle").foregroundStyle(.gray)
        case .sending:
            ProgressView().controlSize(.mini)
        case .processing:
            ProgressView().controlSize(.mini)
        case .parsing:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
    
    private var statusLabel: String {
        switch geminiService.status {
        case .idle: return "Ready"
        case .sending: return "Sending request…"
        case .processing: return "Processing…"
        case .parsing: return "Parsing results…"
        case .done: return "Complete"
        }
    }
    
    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
