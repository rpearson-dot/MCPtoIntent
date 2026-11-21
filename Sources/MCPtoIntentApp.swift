import SwiftUI

@main
struct MCPtoIntentApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ServersView()
                .environmentObject(model)
        }
    }
}
