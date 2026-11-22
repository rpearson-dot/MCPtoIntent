import AppIntents
import SwiftUI

@main
struct MCPtoIntentApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Register the app's shortcuts with the system so "Run a tool" appears in the Shortcuts app and Siri. Without
        // this the App Shortcut often never surfaces — especially for sideloaded installs, which don't get the normal
        // post-install indexing. Safe and cheap to call on every launch.
        MCPShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ServersView()
                .environmentObject(model)
        }
    }
}
