import SwiftUI
import SwiftData

@main
struct HDD_CatalogueApp: App {
    @State private var driveMonitor = DriveMonitor()
    @State private var scanEngine = ScanEngine()
    @State private var undoService = UndoManagerService()
    @State private var showMainWindow = false
    
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Drive.self,
            Project.self,
            Client.self,
            DuplicateGroup.self,
            SmartBin.self,
            MediaFile.self
        ])
        let config = ModelConfiguration("HDD_Catalogue", isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema migration failed — delete old store and recreate.
            // This is safe because all project data is re-scanned from drives.
            print("⚠️ SwiftData migration failed, recreating store: \(error)")
            let storeURL = config.url
            let fm = FileManager.default
            // Delete all store-related files
            for suffix in ["", "-wal", "-shm"] {
                let fileURL = URL(fileURLWithPath: storeURL.path + suffix)
                try? fm.removeItem(at: fileURL)
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
        }
    }()
    
    init() {
        NotificationService.requestPermission()
    }
    
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
            .environment(undoService)
            .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo \(undoService.undoManager.undoActionName)") {
                    undoService.undoManager.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!undoService.undoManager.canUndo)
                
                Button("Redo \(undoService.undoManager.redoActionName)") {
                    undoService.undoManager.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!undoService.undoManager.canRedo)
            }
            
            CommandGroup(after: .textEditing) {
                Button("Quick Search") {
                    NotificationCenter.default.post(name: .toggleQuickSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Button("AI Visual Search") {
                    NotificationCenter.default.post(name: .toggleVisualSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                
                Button("Deep Media Search") {
                    NotificationCenter.default.post(name: .toggleDeepMediaSearch, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        
        // Settings Window
        Settings {
            SettingsView()
        }
        .modelContainer(sharedModelContainer)
    }
}
