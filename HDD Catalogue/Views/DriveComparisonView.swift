import SwiftUI
import SwiftData

/// Phase 3: Drive Comparison — side-by-side view of two drives showing shared and unique projects.
struct DriveComparisonView: View {
    let drives: [Drive]
    let projects: [Project]
    
    @Environment(\.dismiss) private var dismiss
    @State private var driveA: Drive?
    @State private var driveB: Drive?
    
    // MARK: - Computed
    
    private var projectsOnA: [Project] {
        guard let a = driveA else { return [] }
        return projects.filter { $0.drive?.id == a.id }
    }
    
    private var projectsOnB: [Project] {
        guard let b = driveB else { return [] }
        return projects.filter { $0.drive?.id == b.id }
    }
    
    private var folderNamesA: Set<String> {
        Set(projectsOnA.map(\.folderName))
    }
    
    private var folderNamesB: Set<String> {
        Set(projectsOnB.map(\.folderName))
    }
    
    private var sharedNames: Set<String> {
        folderNamesA.intersection(folderNamesB)
    }
    
    private var onlyOnA: [Project] {
        projectsOnA.filter { !sharedNames.contains($0.folderName) }
    }
    
    private var onlyOnB: [Project] {
        projectsOnB.filter { !sharedNames.contains($0.folderName) }
    }
    
    private var sharedOnA: [Project] {
        projectsOnA.filter { sharedNames.contains($0.folderName) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Drive Comparison")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(20)
            
            Divider()
            
            // Drive pickers
            HStack(spacing: 20) {
                drivePicker(label: "Drive A", selection: $driveA, other: driveB)
                
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                
                drivePicker(label: "Drive B", selection: $driveB, other: driveA)
            }
            .padding(20)
            
            // Comparison results
            if driveA != nil && driveB != nil {
                // Summary stats
                summaryBar
                
                Divider()
                
                // Results
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Shared projects
                        if !sharedNames.isEmpty {
                            comparisonSection(
                                title: "On Both Drives",
                                icon: "checkmark.shield.fill",
                                color: .green,
                                projects: sharedOnA,
                                badge: "Backed up",
                                badgeColor: .green
                            )
                        }
                        
                        // Only on A
                        if !onlyOnA.isEmpty {
                            comparisonSection(
                                title: "Only on \(driveA?.name ?? "Drive A")",
                                icon: "exclamationmark.triangle.fill",
                                color: .orange,
                                projects: onlyOnA,
                                badge: "Not backed up",
                                badgeColor: .orange
                            )
                        }
                        
                        // Only on B
                        if !onlyOnB.isEmpty {
                            comparisonSection(
                                title: "Only on \(driveB?.name ?? "Drive B")",
                                icon: "exclamationmark.triangle.fill",
                                color: .orange,
                                projects: onlyOnB,
                                badge: "Not backed up",
                                badgeColor: .orange
                            )
                        }
                        
                        if sharedNames.isEmpty && onlyOnA.isEmpty && onlyOnB.isEmpty {
                            VStack(spacing: 8) {
                                Spacer(minLength: 40)
                                Image(systemName: "tray")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.tertiary)
                                Text("No projects on either drive")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 40)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                }
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Select two drives to compare")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .onAppear {
            // Auto-select first two drives
            let sorted = drives.sorted { $0.projects.count > $1.projects.count }
            if sorted.count >= 2 {
                driveA = sorted[0]
                driveB = sorted[1]
            } else if sorted.count == 1 {
                driveA = sorted[0]
            }
        }
    }
    
    // MARK: - Drive Picker
    
    private func drivePicker(label: String, selection: Binding<Drive?>, other: Drive?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            Picker("", selection: selection) {
                Text("Select…").tag(nil as Drive?)
                ForEach(drives.filter { $0.id != other?.id }, id: \.id) { drive in
                    HStack {
                        Image(systemName: drive.isConnected ? "externaldrive.fill" : "externaldrive")
                        Text("\(drive.name) (\(drive.formattedCapacity))")
                    }
                    .tag(drive as Drive?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Summary Bar
    
    private var summaryBar: some View {
        HStack(spacing: 20) {
            summaryPill(
                value: "\(sharedNames.count)",
                label: "Shared",
                icon: "checkmark.shield.fill",
                color: .green
            )
            summaryPill(
                value: "\(onlyOnA.count)",
                label: "Only \(driveA?.name ?? "A")",
                icon: "1.circle.fill",
                color: .orange
            )
            summaryPill(
                value: "\(onlyOnB.count)",
                label: "Only \(driveB?.name ?? "B")",
                icon: "2.circle.fill",
                color: .orange
            )
            
            let sizeA = projectsOnA.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let sizeB = projectsOnB.reduce(Int64(0)) { $0 + $1.sizeBytes }
            summaryPill(
                value: ByteCountFormatter.string(fromByteCount: abs(sizeA - sizeB), countStyle: .file),
                label: "Size Diff",
                icon: "arrow.up.arrow.down",
                color: .blue
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.3))
    }
    
    private func summaryPill(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Comparison Section
    
    private func comparisonSection(title: String, icon: String, color: Color, projects: [Project], badge: String, badgeColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Text("(\(projects.count))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 1) {
                ForEach(projects, id: \.id) { project in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(project.client?.color ?? .gray)
                            .frame(width: 7, height: 7)
                        
                        Text(project.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let client = project.client {
                            Text(client.name)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        
                        Text(project.formattedSize)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.12), in: Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.02))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 0.5)
            )
        }
    }
}
