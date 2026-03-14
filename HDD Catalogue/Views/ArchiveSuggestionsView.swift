import SwiftUI
import SwiftData

/// Phase 3: Archive Suggestions — lists projects that are good candidates for archiving.
/// Criteria: last modified > 6 months, deliverables present, not active/in-progress.
struct ArchiveSuggestionsView: View {
    let candidates: [Project]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(UndoManagerService.self) private var undoService
    @State private var archivedIds: Set<UUID> = []
    
    private var remainingCandidates: [Project] {
        candidates.filter { !archivedIds.contains($0.id) }
    }
    
    private var totalSavings: Int64 {
        remainingCandidates.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.indigo)
                Text("Archive Suggestions")
                    .font(.system(size: 15, weight: .bold))
                
                Spacer()
                
                if !remainingCandidates.isEmpty {
                    Button {
                        archiveAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 10))
                            Text("Archive All (\(remainingCandidates.count))")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.indigo.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Summary card
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(remainingCandidates.count) projects")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("could be archived")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text(ByteCountFormatter.string(fromByteCount: totalSavings, countStyle: .file))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.indigo)
                    Text("total size")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.indigo.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            
            // Criteria info
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("Projects last modified >6 months ago with deliverables and not actively in progress")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            // Project list
            if !remainingCandidates.isEmpty {
                VStack(spacing: 1) {
                    ForEach(remainingCandidates.prefix(10), id: \.id) { project in
                        archiveRow(project)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if remainingCandidates.count > 10 {
                    Text("+ \(remainingCandidates.count - 10) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)
                        Text("All suggestions archived!")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.indigo.opacity(0.12), lineWidth: 1)
        )
    }
    
    // MARK: - Row
    
    private func archiveRow(_ project: Project) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(project.client?.color ?? .gray)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(project.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if let client = project.client {
                        Text(client.name)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if project.isDelivered {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 7))
                            Text("Delivered")
                                .font(.system(size: 8))
                        }
                        .foregroundStyle(.green)
                    }
                }
            }
            
            Spacer()
            
            if let drive = project.drive {
                Text(drive.name)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            
            Text(project.formattedSize)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            
            Text(project.formattedDate)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
            
            Button {
                archiveProject(project)
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 11))
                    .foregroundStyle(.indigo)
                    .frame(width: 28, height: 28)
                    .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Mark as Archived")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }
    
    // MARK: - Actions
    
    private func archiveProject(_ project: Project) {
        withAnimation(.spring(response: 0.3)) {
            let previousStatus = project.projectStatus
            project.projectStatus = .archived
            undoService.registerGenericUndo(name: "Archive \(project.displayName)") {
                project.projectStatus = previousStatus
            }
            archivedIds.insert(project.id)
            try? modelContext.save()
        }
    }
    
    private func archiveAll() {
        withAnimation(.spring(response: 0.4)) {
            for project in remainingCandidates {
                project.projectStatus = .archived
                archivedIds.insert(project.id)
            }
            try? modelContext.save()
        }
    }
}
