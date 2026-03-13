import SwiftUI
import SwiftData

@main
struct HDD_CatalogueApp: App {
    @State private var driveMonitor = DriveMonitor()
    @State private var scanEngine = ScanEngine()
    @State private var showMainWindow = false
    
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Drive.self,
            Project.self,
            Client.self,
            DuplicateGroup.self
        ])
        let config = ModelConfiguration("HDD_Catalogue", isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        // Menu Bar
        MenuBarExtra("HDD Catalogue", systemImage: scanEngine.isScanning ? "externaldrive.badge.timemachine" : "externaldrive.fill") {
            MenuBarView(
                driveMonitor: driveMonitor,
                scanEngine: scanEngine,
                showMainWindow: $showMainWindow
            )
        }
        .modelContainer(sharedModelContainer)
        
        // Main Window
        Window("HDD Catalogue", id: "main") {
            ContentView(
                driveMonitor: driveMonitor,
                scanEngine: scanEngine
            )
            .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .modelContainer(sharedModelContainer)
        
        // Settings Window
        Settings {
            SettingsView()
        }
        .modelContainer(sharedModelContainer)
    }
}
