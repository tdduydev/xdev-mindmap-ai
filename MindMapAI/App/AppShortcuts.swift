import AppIntents
import MindMapIntents

/// Pulls the intents from `MindMapIntents` into the app's App Intents
/// metadata; without it the system does not see intents declared in a package.
struct MindMapAIAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [MindMapIntentsPackage.self]
    }
}

/// Ready-made shortcuts in Shortcuts, Spotlight and Siri, with no setup (FR-SYS-03).
/// Phrases are translated in `AppShortcuts.xcstrings`; each one names the app.
struct MindMapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewMapIntent(),
            phrases: [
                "New map in \(.applicationName)",
                "Start a \(.applicationName) map",
            ],
            shortTitle: "New Mind Map",
            systemImageName: "plus.rectangle.on.rectangle"
        )
        AppShortcut(
            intent: MapFromClipboardIntent(),
            phrases: ["Make a \(.applicationName) map from the clipboard"],
            shortTitle: "Map from Clipboard",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: AddIdeaIntent(),
            phrases: ["Add an idea to \(.applicationName)"],
            shortTitle: "Add Idea",
            systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: OpenRecentMapIntent(),
            phrases: ["Open my recent \(.applicationName) map"],
            shortTitle: "Open Recent Map",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
