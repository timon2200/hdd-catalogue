import SwiftUI
import SwiftData

/// "Home" dashboard showing recently modified projects grouped by recency.
struct RecentlyModifiedView: View {
    let projects: [Project]
    let onOpenProject: (Project) -> Void
    
    private var groupedProjects: [(title: String, projects: [Project])] {
        let now = Date()
        let calendar = Calendar.current
        
        let today = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        
        var groups: [(String, [Project])] = []
        
        let todayProjects = projects.filter { ($0.projectDate ?? .distantPast) >= today }
        let thisWeekProjects = projects.filter {
            let date = $0.projectDate ?? .distantPast
            return date >= weekAgo && date < today
        }
        let thisMonthProjects = projects.filter {
            let date = $0.projectDate ?? .distantPast
            return date >= monthAgo && date < weekAgo
        }
        let earlierProjects = projects.filter { ($0.projectDate ?? .distantPast) < monthAgo }
        
        if !todayProjects.isEmpty { groups.append(("Today", todayProjects)) }
        if !thisWeekProjects.isEmpty { groups.append(("This Week", thisWeekProjects)) }
        if !thisMonthProjects.isEmpty { groups.append(("This Month", thisMonthProjects)) }
        if !earlierProjects.isEmpty { groups.append(("Earlier", Array(earlierProjects.prefix(20)))) }
        
        return groups
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header stats
                statsHeader
                
                // Grouped project lists
                ForEach(groupedProjects, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        
                        LazyVStack(spacing: 4) {
                            ForEach(group.projects, id: \.id) { project in
                                recentProjectRow(project)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Stats Header
    
    private var statsHeader: some View {
        HStack(spacing: 16) {
            statPill(
                value: "\(projects.count)",
                label: "Total Projects",
                icon: "folder.fill",
                color: .blue
            )
            
            statPill(
                value: "\(projects.filter { $0.projectStatus == .inProgress }.count)",
                label: "In Progress",
                icon: "circle.lefthalf.filled",
                color: .orange
            )
            
            statPill(
                value: "\(Set(projects.compactMap(\.drive?.id)).count)",
                label: "Drives",
                icon: "externaldrive.fill",
                color: .green
            )
            
            let recentCount = projects.filter { ($0.projectDate ?? .distantPast) > Calendar.current.date(byAdding: .day, value: -7, to: Date())! }.count
            statPill(
                value: "\(recentCount)",
                label: "This Week",
                icon: "clock.fill",
                color: .purple
            )
        }
    }
    
    private func statPill(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Project Row
    
    private func recentProjectRow(_ project: Project) -> some View {
        Button {
            onOpenProject(project)
        } label: {
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: project.projectStatus.icon)
                    .font(.caption)
                    .foregroundStyle(project.projectStatus.color)
                    .frame(width: 16)
                
                // Client dot
                Circle()
                    .fill(project.client?.color ?? .gray)
                    .frame(width: 8, height: 8)
                
                // Project info
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if let client = project.client {
                            Text(client.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(project.projectType)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // Tags
                if !project.tags.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(project.tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                }
                
                // Drive info
                if let drive = project.drive {
                    HStack(spacing: 3) {
                        Image(systemName: drive.isConnected ? "externaldrive.fill" : "externaldrive")
                            .font(.system(size: 9))
                            .foregroundStyle(drive.isConnected ? .green : .gray)
                        Text(drive.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(project.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 60, alignment: .trailing)
                
                Text(project.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
