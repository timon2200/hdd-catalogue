import SwiftUI
import SwiftData

/// Side-by-side comparison panel for AI-detected duplicate projects.
struct DuplicateResolutionView: View {
    let duplicateGroups: [DuplicateGroup]
    let onDismiss: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(UndoManagerService.self) private var undoService
    @State private var selectedGroupIndex = 0
    
    var currentGroup: DuplicateGroup? {
        guard selectedGroupIndex < duplicateGroups.count else { return nil }
        return duplicateGroups[selectedGroupIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Duplicate Projects Detected")
                    .font(.headline)
                Spacer()
                
                if duplicateGroups.count > 1 {
                    Text("\(selectedGroupIndex + 1) of \(duplicateGroups.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            if let group = currentGroup {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Group name
                        Text(group.groupName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        
                        // Suggested action
                        if !group.suggestedAction.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                Text(group.suggestedAction)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                        }
                        
                        // Project comparison cards
                        ForEach(group.projectsBySize, id: \.id) { project in
                            projectComparisonCard(project, isLatest: project.id == group.latestVersionId)
                        }
                        
                        // Size difference callout
                        if group.sizeDifference > 0 {
                            HStack {
                                Image(systemName: "arrow.up.arrow.down")
                                    .foregroundStyle(.orange)
                                Text("Size difference: \(group.formattedSizeDifference)")
                                    .font(.callout)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 16)
                }
                
                Divider()
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("Dismiss") {
                        undoService.registerDismissal(group: group, context: modelContext)
                        group.isDismissed = true
                        try? modelContext.save()
                        moveToNextGroup()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    if duplicateGroups.count > 1 {
                        Button {
                            if selectedGroupIndex > 0 { selectedGroupIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(selectedGroupIndex == 0)
                        
                        Button {
                            if selectedGroupIndex < duplicateGroups.count - 1 { selectedGroupIndex += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(selectedGroupIndex >= duplicateGroups.count - 1)
                    }
                    
                    Button("Dismiss All") {
                        undoService.registerDismissAll(groups: duplicateGroups, context: modelContext)
                        for g in duplicateGroups {
                            g.isDismissed = true
                        }
                        try? modelContext.save()
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial)
            } else {
                VStack {
                    Spacer()
                    Text("All duplicates resolved!")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Project Comparison Card
    
    @ViewBuilder
    private func projectComparisonCard(_ project: Project, isLatest: Bool) -> some View {
        HStack(spacing: 12) {
            // Latest badge
            if isLatest {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.folderName)
                        .fontWeight(.medium)
                    
                    if isLatest {
                        Text("LATEST")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                
                HStack(spacing: 16) {
                    if let driveName = project.drive?.name {
                        Label(driveName, systemImage: "externaldrive.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Label(project.formattedSize, systemImage: "doc.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label(project.formattedDate, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label("\(project.fileCount) files", systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            isLatest ? Color.green.opacity(0.05) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isLatest ? Color.green.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    private func moveToNextGroup() {
        if selectedGroupIndex < duplicateGroups.count - 1 {
            selectedGroupIndex += 1
        } else if duplicateGroups.allSatisfy({ $0.isDismissed }) {
            onDismiss()
        }
    }
}
