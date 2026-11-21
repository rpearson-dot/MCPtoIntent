import AppIntents

/// The Siri phrases the app ships. App Shortcut phrases are fixed templates at build time, so these are generic and
/// reference the chosen tool by its friendly name — e.g. "Run shopping list with MCP to Intent". For a phrase in your
/// own words ("add to the shopping list"), open the Shortcuts app, add the "Run a tool" action, pick the tool, and
/// record a phrase; the app exposes the intent for exactly that.
struct MCPShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunToolIntent(),
            phrases: [
                "Run \(\.$tool) with \(.applicationName)",
                "Ask \(.applicationName) to run \(\.$tool)",
                "\(\.$tool) on \(.applicationName)",
            ],
            shortTitle: "Run a tool",
            systemImageName: "bolt.horizontal.circle"
        )
    }
}
