import SwiftUI
import SwiftData

/// Inline tag editor with autocomplete from existing tags across all projects.
struct TagInputView: View {
    @Binding var tags: [String]
    let allTags: [String]  // All existing tags for autocomplete
    
    @State private var inputText = ""
    @State private var showSuggestions = false
    @FocusState private var isInputFocused: Bool
    
    private var suggestions: [String] {
        guard !inputText.isEmpty else { return [] }
        let query = inputText.lowercased()
        return allTags
            .filter { $0.lowercased().contains(query) && !tags.contains($0) }
            .prefix(5)
            .map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Tag capsules + input field
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    tagCapsule(tag)
                }
                
                // Input field
                TextField("Add tag…", text: $inputText)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 80, maxWidth: 160)
                    .focused($isInputFocused)
                    .onSubmit {
                        addTag(inputText)
                    }
                    .onChange(of: inputText) { _, newValue in
                        showSuggestions = !newValue.isEmpty && !suggestions.isEmpty
                    }
            }
            
            // Autocomplete suggestions
            if showSuggestions && isInputFocused {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            addTag(suggestion)
                        } label: {
                            HStack {
                                Image(systemName: "tag")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(suggestion)
                                    .font(.caption)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.clear)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary, lineWidth: 1)
                )
            }
        }
    }
    
    @ViewBuilder
    private func tagCapsule(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .fontWeight(.medium)
            
            Button {
                withAnimation(.spring(response: 0.3)) {
                    tags.removeAll { $0 == tag }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tagColor(for: tag).opacity(0.15), in: Capsule())
        .foregroundStyle(tagColor(for: tag))
        .overlay(Capsule().stroke(tagColor(for: tag).opacity(0.3), lineWidth: 1))
        .transition(.scale.combined(with: .opacity))
    }
    
    private func addTag(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        // Normalize: add # prefix if not present
        let normalized = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        
        guard !tags.contains(normalized) else {
            inputText = ""
            return
        }
        
        withAnimation(.spring(response: 0.3)) {
            tags.append(normalized)
        }
        inputText = ""
        showSuggestions = false
    }
    
    private func tagColor(for tag: String) -> Color {
        // Deterministic color from tag name hash
        let hash = abs(tag.hashValue)
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan]
        return colors[hash % colors.count]
    }
}

// MARK: - Flow Layout

/// A simple flow layout that wraps items to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }
    
    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
        var sizes: [CGSize]
    }
    
    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)
            
            if x + size.width > maxWidth && x > 0 {
                // Wrap to next line
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = y + rowHeight
        }
        
        return LayoutResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }
}
