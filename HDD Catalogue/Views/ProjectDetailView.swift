import SwiftUI
import SwiftData

/// Expandable detail view for a project showing internal structure, media breakdown,
/// camera sources, NLE files, and completeness gauge.
struct ProjectDetailView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allProjects: [Project]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let drive = project.drive {
                        HStack(spacing: 4) {
                            Image(systemName: drive.isConnected ? "externaldrive.fill" : "externaldrive")
                                .foregroundStyle(drive.isConnected ? .green : .gray)
                            Text(drive.name)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                
                Spacer()
                
                completenessGauge
                
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status & Tags
                    statusAndTagsSection
                    
                    // Notes
                    if !project.notes.isEmpty {
                        notesSection
                    }
                    
                    // Quick stats
                    quickStatsSection
                    
                    // NLE section
                    if !project.detectedNLEs.isEmpty {
                        nleSection
                    }
                    
                    // Media breakdown
                    if let summary = project.mediaSummary, !summary.isEmpty {
                        mediaBreakdownSection(summary)
                    }
                    
                    // Camera sources
                    if !project.cameraSources.isEmpty {
                        cameraSourcesSection
                    }
                    
                    // Shoot days
                    if project.shootDayCount > 0 {
                        shootDaysSection
                    }
                    
                    // Project structure
                    projectStructureSection
                    
                    // Path info
                    pathInfoSection
                }
                .padding()
            }
        }
        .frame(idealWidth: 520, minHeight: 500, idealHeight: 600, maxHeight: 700)
    }
    
    // MARK: - Completeness Gauge
    
    private var completenessGauge: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: project.projectCompleteness)
                    .stroke(completenessColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: project.projectCompleteness)
                
                Text("\(Int(project.projectCompleteness * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(completenessColor)
            }
            .frame(width: 44, height: 44)
            
            Text("Complete")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
    
    private var completenessColor: Color {
        switch project.projectCompleteness {
        case 0.9...1.0: return .green
        case 0.5..<0.9: return .yellow
        default:        return .orange
        }
    }
    
    // MARK: - Quick Stats
    
    private var quickStatsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 12) {
            statCard(value: project.formattedSize, label: "Size", icon: "internaldrive", color: .blue)
            statCard(value: "\(project.fileCount)", label: "Files", icon: "doc.fill", color: .purple)
            statCard(value: project.formattedDate, label: "Modified", icon: "calendar", color: .orange)
            statCard(value: project.isDelivered ? "Yes" : (project.hasExports ? "Partial" : "No"), label: "Delivered", icon: "checkmark.seal.fill", color: project.isDelivered ? .green : .gray)
        }
    }
    
    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - NLE Section
    
    private var nleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("NLE Project Files", icon: "play.rectangle.fill")
            
            ForEach(project.nleIcons, id: \.name) { nle in
                HStack(spacing: 10) {
                    Image(systemName: nle.symbol)
                        .foregroundStyle(.purple)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nle.name)
                            .font(.callout)
                            .fontWeight(.medium)
                        if let date = project.nleProjectFileDate {
                            Text("Last modified: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text(nle.abbreviation)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.purple)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // MARK: - Media Breakdown
    
    private func mediaBreakdownSection(_ summary: MediaSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Media Breakdown", icon: "chart.bar.fill")
            
            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    if summary.videoCount > 0 {
                        barSegment(width: segmentWidth(summary.videoCount, of: summary.totalCount, in: geo.size.width), color: .blue)
                    }
                    if summary.audioCount > 0 {
                        barSegment(width: segmentWidth(summary.audioCount, of: summary.totalCount, in: geo.size.width), color: .green)
                    }
                    if summary.graphicsCount > 0 {
                        barSegment(width: segmentWidth(summary.graphicsCount, of: summary.totalCount, in: geo.size.width), color: .purple)
                    }
                    if summary.fontCount > 0 {
                        barSegment(width: segmentWidth(summary.fontCount, of: summary.totalCount, in: geo.size.width), color: .orange)
                    }
                    if summary.renderCount > 0 {
                        barSegment(width: segmentWidth(summary.renderCount, of: summary.totalCount, in: geo.size.width), color: .cyan)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            
            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                if summary.videoCount > 0 {
                    mediaLegendItem("Video", count: summary.videoCount, icon: "video.fill", color: .blue)
                }
                if summary.audioCount > 0 {
                    mediaLegendItem("Audio", count: summary.audioCount, icon: "waveform", color: .green)
                }
                if summary.graphicsCount > 0 {
                    mediaLegendItem("Graphics", count: summary.graphicsCount, icon: "photo.fill", color: .purple)
                }
                if summary.fontCount > 0 {
                    mediaLegendItem("Fonts", count: summary.fontCount, icon: "textformat", color: .orange)
                }
                if summary.renderCount > 0 {
                    mediaLegendItem("Renders", count: summary.renderCount, icon: "film", color: .cyan)
                }
            }
        }
    }
    
    private func segmentWidth(_ count: Int, of total: Int, in width: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(4, (CGFloat(count) / CGFloat(total)) * width)
    }
    
    private func barSegment(width: CGFloat, color: Color) -> some View {
        color.frame(width: width)
    }
    
    private func mediaLegendItem(_ label: String, count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(label)
                .font(.caption)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Camera Sources
    
    private var cameraSourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Camera Sources", icon: "camera.fill")
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(project.cameraSources, id: \.self) { camera in
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                        Text(camera)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.indigo)
                }
                
                if project.hasDroneFootage {
                    HStack(spacing: 6) {
                        Image(systemName: "airplane")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                        Text("Drone/Aerial")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.cyan)
                }
            }
            
            if project.cameraSources.count > 1 {
                Text("Multi-cam shoot (\(project.cameraSources.count) sources)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
    
    // MARK: - Shoot Days
    
    private var shootDaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Shoot Days (\(project.shootDayCount))", icon: "calendar.badge.clock")
            
            ForEach(project.shootDayFolders, id: \.self) { folder in
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(folder)
                        .font(.callout)
                }
            }
        }
    }
    
    // MARK: - Project Structure
    
    private var projectStructureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Project Checklist", icon: "checklist")
            
            completenessRow("Source Footage", isComplete: project.mediaSummary?.videoCount ?? 0 > 0 || !project.cameraSources.isEmpty)
            completenessRow("NLE Project File", isComplete: !project.detectedNLEs.isEmpty)
            completenessRow("Exports / Deliverables", isComplete: project.hasExports)
        }
    }
    
    private func completenessRow(_ label: String, isComplete: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .gray.opacity(0.5))
            Text(label)
                .font(.callout)
                .foregroundStyle(isComplete ? .primary : .secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isComplete ? Color.green.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - Path Info
    
    private var pathInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Location", icon: "folder")
            
            Text(project.folderPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            
            if project.drive?.isConnected == true {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.folderPath)
                }
                .font(.caption)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout)
                .fontWeight(.semibold)
        }
        .padding(.bottom, 2)
    }
    
    // MARK: - Status & Tags
    
    private var allExistingTags: [String] {
        Array(Set(allProjects.flatMap(\.tags))).sorted()
    }
    
    private var statusAndTagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status picker
            HStack(spacing: 12) {
                sectionHeader("Status", icon: "circle.dotted")
                Spacer()
                Menu {
                    ForEach(ProjectStatus.allCases) { status in
                        Button {
                            project.projectStatus = status
                            try? modelContext.save()
                        } label: {
                            HStack {
                                Image(systemName: status.icon)
                                Text(status.rawValue)
                                if project.projectStatus == status {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: project.projectStatus.icon)
                            .foregroundStyle(project.projectStatus.color)
                        Text(project.projectStatus.rawValue)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(project.projectStatus.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            // Tags
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Tags", icon: "tag")
                TagInputView(
                    tags: Binding(
                        get: { project.tags },
                        set: { 
                            project.tags = $0
                            try? modelContext.save()
                        }
                    ),
                    allTags: allExistingTags
                )
            }
        }
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Notes", icon: "note.text")
            Text(project.notes)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
