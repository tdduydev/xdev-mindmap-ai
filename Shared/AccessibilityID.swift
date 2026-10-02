/// Stable, untranslated names UI tests find views by. This file is compiled
/// into the app and the UI test target, so renaming one breaks the build
/// instead of a test run.
///
/// Convention (docs/testing.md): `area.element` in lowerCamelCase. Repeated
/// elements, such as library rows or topics, share one identifier; a test
/// tells them apart by their label, which is the title the person sees.
nonisolated enum AccessibilityID {
    enum Sidebar {
        static let list = "sidebar.list"
        static let settings = "sidebar.settings"
        static let syncStatus = "sidebar.syncStatus"
        /// A row of the sidebar, by `LibrarySection` raw value.
        static func section(_ name: String) -> String { "sidebar.section.\(name)" }
    }

    enum Library {
        static let list = "library.list"
        static let map = "library.map"
        /// The Mac toolbar's Settings button; the sidebar footer's is `Sidebar.settings`.
        static let settings = "library.settings"
        static let newMap = "library.newMap"
    }

    enum Editor {
        static let presentation = "editor.presentation"
        static let undo = "editor.undo"
        static let redo = "editor.redo"
        static let addChild = "editor.addChild"
        static let addSibling = "editor.addSibling"
        static let delete = "editor.delete"
        static let find = "editor.find"
        static let inspector = "editor.inspector"
    }

    /// Find in the open map (the bar above the canvas or the outline).
    enum Find {
        static let field = "find.field"
        /// "No Results", "2 of 3" or "3 matches".
        static let status = "find.status"
        static let previous = "find.previous"
        static let next = "find.next"
        static let done = "find.done"
    }

    enum Outline {
        static let list = "outline.list"
        static let topic = "outline.topic"
        static let disclosure = "outline.disclosure"
        static let addCentralTopic = "outline.addCentralTopic"
    }

    enum Canvas {
        static let canvas = "canvas"
        static let topic = "canvas.topic"
        static let addCentralTopic = "canvas.addCentralTopic"
    }

    /// A topic's URL link (FR-ORG-26).
    enum Link {
        static let field = "link.field"
        static let save = "link.save"
        static let remove = "link.remove"
        static let cancel = "link.cancel"
        static let error = "link.error"
        static let open = "link.open"
    }

    enum Chat {
        static let panel = "chat.panel"
        static let field = "chat.field"
        static let send = "chat.send"
        static let stop = "chat.stop"
        static let answer = "chat.answer"
        static let citation = "chat.citation"
        static let toolbar = "chat.toolbar"
    }

    enum ScreenshotAI {
        static let menu = "screenshot.ai.menu"
        static let review = "screenshot.ai.review"
    }

    enum Settings {
        static let appearance = "settings.appearance"
        static let newMapTheme = "settings.newMapTheme"
        static let includeNotes = "settings.includeNotes"
        static let pngResolution = "settings.pngResolution"
        static let pdfPages = "settings.pdfPages"
        static let paperSize = "settings.paperSize"
        static let background = "settings.background"
        /// The Mac tab or the iPad and iPhone row of a pane, by `SettingsPane` raw value.
        static func pane(_ name: String) -> String { "settings.pane.\(name)" }
        static let done = "settings.done"
        static let iCloudSync = "settings.iCloudSync"
        static let iCloudStatus = "settings.iCloudStatus"
        static let aiStatus = "settings.aiStatus"
        static let useAI = "settings.useAI"
        static let voiceInputLanguage = "settings.voiceInputLanguage"
        static let privacyAI = "settings.privacy.ai"
        static let privacyVoiceInput = "settings.privacy.voiceInput"
        static let aiAppsSwitch = "settings.aiApps.switch"
        static let aiAppsStatus = "settings.aiApps.status"
        static let aiAppsPort = "settings.aiApps.port"
        static let aiAppsAdd = "settings.aiApps.add"
        static let aiAppsPrivacy = "settings.aiApps.privacy"
    }
}
