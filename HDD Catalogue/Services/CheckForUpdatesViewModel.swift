import SwiftUI
import Sparkle

/// A view model that publishes update-check availability from Sparkle.
/// Used by the app menu "Check for Updates…" command and the Settings button.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    
    let updaterController: SPUStandardUpdaterController
    
    init() {
        // Start the updater — handles its own lifecycle
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Observe when the updater is ready to check
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
