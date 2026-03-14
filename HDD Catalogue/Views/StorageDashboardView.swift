import SwiftUI
import SwiftData

/// Phase 3: Storage Dashboard — total storage overview, per-client breakdown, drive cards, SSD offload recommendations.
struct StorageDashboardView: View {
    let drives: [Drive]
    let projects: [Project]
    let clients: [Client]
    
    @State private var showDriveComparison = false
    @State private var showFileTypeSearch = false
    
    // MARK: - Computed
    
    private var connectedDrives: [Drive] { drives.filter(\.isConnected) }
    private var disconnectedDrives: [Drive] { drives.filter { !$0.isConnected } }
    
    private var totalCapacity: Int64 { drives.reduce(0) { $0 + $1.totalCapacityBytes } }
    private var totalUsed: Int64 { drives.reduce(0) { $0 + ($1.totalCapacityBytes - $1.availableCapacityBytes) } }
    private var totalAvailable: Int64 { drives.reduce(0) { $0 + $1.availableCapacityBytes } }
    
    private var mostFreeSpaceDrive: Drive? {
        connectedDrives.max(by: { $0.availableCapacityBytes < $1.availableCapacityBytes })
    }
    
    /// Client storage: total project size per client, sorted descending.
    private var clientStorage: [(client: Client, totalSize: Int64)] {
        clients.compactMap { client in
            let size = client.projects.reduce(Int64(0)) { $0 + $1.sizeBytes }
            guard size > 0 else { return nil }
            return (client, size)
        }
        .sorted { $0.totalSize > $1.totalSize }
    }
    
    private var maxClientSize: Int64 { clientStorage.first?.totalSize ?? 1 }
    
    /// SSDs that are >70% full.
    private var overloadedSSDs: [Drive] {
        connectedDrives.filter { $0.driveType == "SSD" && $0.usagePercentage > 0.7 }
    }
    
    /// HDDs with significant free space (>20% free).
    private var availableHDDs: [Drive] {
        connectedDrives.filter { $0.driveType == "HDD" && $0.usagePercentage < 0.8 }
    }
    
    /// Projects on overloaded SSDs that could be offloaded (large, old, delivered).
    private var offloadCandidates: [Project] {
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let ssdDriveIds = Set(overloadedSSDs.map(\.id))
        
        return projects.filter { project in
            guard let driveId = project.drive?.id else { return false }
            return ssdDriveIds.contains(driveId) &&
                   (project.projectDate ?? Date()) < sixMonthsAgo &&
                   project.projectStatus != .inProgress &&
                   project.projectStatus != .review
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }
    
    /// Archive candidates across all drives.
    private var archiveCandidates: [Project] {
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        return projects.filter { project in
            (project.projectDate ?? Date()) < sixMonthsAgo &&
            project.isDelivered &&
            project.projectStatus != .inProgress &&
            project.projectStatus != .review &&
            project.projectStatus != .archived
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title row
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage Dashboard")
                            .font(.system(size: 26, weight: .bold))
                        Text("\(drives.count) drives catalogued · \(connectedDrives.count) connected")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: 8) {
                        Button {
                            showFileTypeSearch = true
                        } label: {
                            Label("File Type Search", systemImage: "doc.text.magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            showDriveComparison = true
                        } label: {
                            Label("Compare Drives", systemImage: "arrow.left.arrow.right")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .disabled(drives.count < 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // MARK: - Stat cards
                statCardsRow
                    .padding(.horizontal, 24)
                
                // MARK: - Drive cards
                if !drives.isEmpty {
                    driveCardsSection
                }
                
                // MARK: - SSD offload recommendations
                if !overloadedSSDs.isEmpty && !availableHDDs.isEmpty && !offloadCandidates.isEmpty {
                    ssdOffloadSection
                }
                
                // MARK: - Per-client storage
                if !clientStorage.isEmpty {
                    clientStorageSection
                }
                
                // MARK: - Archive suggestions
                if !archiveCandidates.isEmpty {
                    ArchiveSuggestionsView(candidates: archiveCandidates)
                        .padding(.horizontal, 24)
                }
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showDriveComparison) {
            DriveComparisonView(drives: drives, projects: projects)
                .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(isPresented: $showFileTypeSearch) {
            FileTypeSearchView(projects: projects)
                .frame(minWidth: 600, minHeight: 450)
        }
    }
    
    // MARK: - Stat Cards Row
    
    private var statCardsRow: some View {
        HStack(spacing: 14) {
            statCard(
                title: "Total Catalogued",
                value: formatBytes(totalCapacity),
                icon: "internaldisk",
                color: .blue,
                subtitle: "\(drives.count) drives"
            )
            statCard(
                title: "Used",
                value: formatBytes(totalUsed),
                icon: "chart.bar.fill",
                color: .orange,
                subtitle: totalCapacity > 0 ? "\(Int(Double(totalUsed) / Double(totalCapacity) * 100))% of total" : ""
            )
            statCard(
                title: "Available",
                value: formatBytes(totalAvailable),
                icon: "checkmark.circle.fill",
                color: .green,
                subtitle: totalCapacity > 0 ? "\(Int(Double(totalAvailable) / Double(totalCapacity) * 100))% free" : ""
            )
            if let bestDrive = mostFreeSpaceDrive {
                statCard(
                    title: "Most Free Space",
                    value: bestDrive.formattedAvailable,
                    icon: "star.fill",
                    color: .yellow,
                    subtitle: bestDrive.name
                )
            }
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.12), lineWidth: 1)
        )
    }
    
    // MARK: - Drive Cards
    
    private var driveCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Drives", icon: "externaldrive.fill", color: .blue)
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(connectedDrives + disconnectedDrives, id: \.id) { drive in
                        driveCard(drive)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
        }
    }
    
    private func driveCard(_ drive: Drive) -> some View {
        let usedBytes = drive.totalCapacityBytes - drive.availableCapacityBytes
        let usageColor: Color = drive.usagePercentage > 0.9 ? .red : drive.usagePercentage > 0.7 ? .orange : .blue
        
        return VStack(spacing: 12) {
            // Usage ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 6)
                    .frame(width: 64, height: 64)
                Circle()
                    .trim(from: 0, to: drive.usagePercentage)
                    .stroke(
                        LinearGradient(
                            colors: [usageColor, usageColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 1) {
                    Text("\(Int(drive.usagePercentage * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("used")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Drive name
            VStack(spacing: 3) {
                Text(drive.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                
                // Type badge
                HStack(spacing: 4) {
                    if !drive.isConnected {
                        Image(systemName: "eject.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.gray)
                    }
                    Text(drive.driveType)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(driveTypeColor(drive.driveType))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(driveTypeColor(drive.driveType).opacity(0.1), in: Capsule())
            }
            
            // Capacity
            VStack(spacing: 2) {
                Text(formatBytes(usedBytes) + " / " + drive.formattedCapacity)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(drive.formattedAvailable + " free")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            
            // Projects count
            Text("\(drive.projects.count) projects")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .frame(width: 140)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(drive.isConnected ? usageColor.opacity(0.2) : Color.gray.opacity(0.15), lineWidth: 1)
        )
        .opacity(drive.isConnected ? 1.0 : 0.6)
    }
    
    // MARK: - SSD Offload Recommendations
    
    private var ssdOffloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "SSD Offload Recommendations", icon: "arrow.right.arrow.left", color: .orange)
                .padding(.horizontal, 24)
            
            VStack(alignment: .leading, spacing: 8) {
                // Info banner
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(overloadedSSDs.count) SSD\(overloadedSSDs.count > 1 ? "s" : "") running low on space")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Consider moving these older projects to an HDD to free up fast storage")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Target HDD
                    if let bestHDD = availableHDDs.max(by: { $0.availableCapacityBytes < $1.availableCapacityBytes }) {
                        VStack(spacing: 2) {
                            Text("Move to")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(bestHDD.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                            Text(bestHDD.formattedAvailable + " free")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.orange.opacity(0.2), lineWidth: 1)
                )
                
                // Candidate projects
                ForEach(offloadCandidates.prefix(5), id: \.id) { project in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(project.client?.color ?? .gray)
                            .frame(width: 8, height: 8)
                        
                        Text(project.displayName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let drive = project.drive {
                            Text(drive.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(project.formattedSize)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .frame(width: 70, alignment: .trailing)
                        
                        Text(project.formattedDate)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                
                if offloadCandidates.count > 5 {
                    Text("+ \(offloadCandidates.count - 5) more projects")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                }
                
                // Total savings
                let totalSavings = offloadCandidates.reduce(Int64(0)) { $0 + $1.sizeBytes }
                HStack {
                    Spacer()
                    Text("Potential SSD savings: ")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(formatBytes(totalSavings))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.orange.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }
    
    // MARK: - Client Storage Breakdown
    
    private var clientStorageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Storage by Client", icon: "person.2.fill", color: .purple)
                .padding(.horizontal, 24)
            
            VStack(spacing: 6) {
                ForEach(clientStorage.prefix(12), id: \.client.id) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.client.color)
                            .frame(width: 8, height: 8)
                        
                        Text(item.client.name)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)
                        
                        // Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.quaternary)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [item.client.color, item.client.color.opacity(0.6)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(4, geo.size.width * CGFloat(Double(item.totalSize) / Double(maxClientSize))))
                            }
                            .frame(height: 8)
                            .clipShape(Capsule())
                        }
                        .frame(height: 8)
                        
                        // Size label
                        Text(formatBytes(item.totalSize))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        
                        Text("\(item.client.projects.count) projects")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(width: 65, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
                
                // Uncategorized projects
                let uncategorizedSize = projects.filter { $0.client == nil }.reduce(Int64(0)) { $0 + $1.sizeBytes }
                if uncategorizedSize > 0 {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.gray)
                            .frame(width: 8, height: 8)
                        
                        Text("Uncategorized")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.quaternary)
                                Capsule()
                                    .fill(.gray.opacity(0.4))
                                    .frame(width: max(4, geo.size.width * CGFloat(Double(uncategorizedSize) / Double(maxClientSize))))
                            }
                            .frame(height: 8)
                            .clipShape(Capsule())
                        }
                        .frame(height: 8)
                        
                        Text(formatBytes(uncategorizedSize))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        
                        let count = projects.filter { $0.client == nil }.count
                        Text("\(count) projects")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(width: 65, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.purple.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 15, weight: .bold))
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private func driveTypeColor(_ type: String) -> Color {
        switch type {
        case "SSD": return .cyan
        case "HDD": return .blue
        case "USB": return .green
        default: return .gray
        }
    }
}
