import SwiftUI
import SwiftData

/// Sheet showing projects visually similar to a selected project.
struct FindSimilarSheet: View {
    let sourceProject: Project
    let visualSearchService: VisualSearchService
    @Binding var isPresented: Project?
    
    @Query private var allProjects: [Project]
    
    @State private var results: [SimilarResult] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var matchedProjects: [(project: Project, result: SimilarResult)] {
        results.compactMap { result in
            guard let project = allProjects.first(where: { $0.id == result.projectId }) else { return nil }
            return (project, result)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find Similar")
                        .font(.headline)
                    Text("to \(sourceProject.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button {
                    isPresented = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
            
            // Source project preview
            HStack(spacing: 12) {
                Group {
                    if let data = sourceProject.thumbnailData, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Text(sourceProject.resolvedThumbnailEmoji)
                            .font(.system(size: 28))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.purple.opacity(0.3), lineWidth: 2)
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(sourceProject.displayName)
                        .font(.callout)
                        .fontWeight(.semibold)
                    
                    if !sourceProject.visualTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(sourceProject.visualTags.prefix(8), id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.purple.opacity(0.1), in: Capsule())
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.purple.opacity(0.04))
            
            Divider()
            
            // Results
            if isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text(visualSearchService.currentStep.isEmpty ? "Comparing visual content…" : visualSearchService.currentStep)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { startSearch() }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else if matchedProjects.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No visually similar projects found")
                        .foregroundStyle(.secondary)
                    Text("This can happen if few projects are visually indexed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(matchedProjects, id: \.project.id) { item in
                            similarResultRow(item.project, result: item.result)
                                .onTapGesture {
                                    NotificationCenter.default.post(
                                        name: .openProjectDetail,
                                        object: item.project.id
                                    )
                                    isPresented = nil
                                }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 480, height: 560)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, y: 5)
        .onAppear { startSearch() }
    }
    
    // MARK: - Result Row
    
    @ViewBuilder
    private func similarResultRow(_ project: Project, result: SimilarResult) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let data = project.thumbnailData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Text(project.resolvedThumbnailEmoji)
                        .font(.title3)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.quaternary, lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(result.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Similarity score
            let pct = Int(result.similarity * 100)
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 2)
                    .frame(width: 32, height: 32)
                Circle()
                    .trim(from: 0, to: result.similarity)
                    .stroke(
                        LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
                
                Text("\(pct)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
    
    // MARK: - Actions
    
    private func startSearch() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let searchResults = try await visualSearchService.findSimilar(
                    sourceProject: sourceProject,
                    allProjects: Array(allProjects)
                )
                await MainActor.run {
                    results = searchResults
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
