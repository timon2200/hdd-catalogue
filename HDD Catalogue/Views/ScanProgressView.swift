import SwiftUI

/// Animated scanning overlay with progress ring and current folder name.
struct ScanProgressView: View {
    let scanEngine: ScanEngine
    
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Animated progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                    .frame(width: 80, height: 80)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: scanEngine.scanProgress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.blue, .cyan, .blue]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: scanEngine.scanProgress)
                
                // Pulse circle
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 70, height: 70)
                    .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
                
                // Drive icon
                Image(systemName: "externaldrive.fill.badge.timemachine")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
            }
            
            // Scanning text
            VStack(spacing: 6) {
                Text("Scanning…")
                    .font(.headline)
                
                if !scanEngine.currentFolder.isEmpty {
                    Text(scanEngine.currentFolder)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300)
                }
                
                if scanEngine.totalCount > 0 {
                    Text("\(scanEngine.scannedCount) / \(scanEngine.totalCount) folders")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                // Percentage
                Text("\(Int(scanEngine.scanProgress * 100))%")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
                    .monospacedDigit()
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            pulseAnimation = true
        }
    }
}
