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
        static let importMap = "library.importMap"
        /// The swipe action that moves a map to Recently Deleted.
        static let delete = "library.delete"
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
        static let voice = "editor.voice"
        static let ai = "editor.ai"
        static let export = "editor.export"
        /// iOS only; the Mac has File ▸ Import into Map….
        static let importIntoMap = "editor.importIntoMap"
    }

    /// The topic and map settings beside an open map.
    enum Inspector {
        static let note = "inspector.note"
        static let tagField = "inspector.tagField"
        static let theme = "inspector.theme"
        static let topicColor = "inspector.topicColor"
        static let topicSymbol = "inspector.topicSymbol"
    }

    /// Choose Symbol… (MM-32).
    enum SymbolPicker {
        static let emoji = "symbolPicker.emoji"
    }

    /// AI suggestions waiting for Accept or Discard (FR-AI-10).
    enum Suggestions {
        static let review = "suggestions.review"
        static let acceptAll = "suggestions.acceptAll"
        static let discardAll = "suggestions.discardAll"
        /// One per suggested topic in the Review list.
        static let accept = "suggestions.accept"
        static let discard = "suggestions.discard"
    }

    enum Export {
        static let format = "export.format"
        static let export = "export.export"
        static let cancel = "export.cancel"
    }

    enum Voice {
        static let listen = "voice.listen"
        static let addTopics = "voice.addTopics"
    }

    enum Paywall {
        static let purchase = "paywall.purchase"
        static let close = "paywall.close"
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
        static let zoomIn = "canvas.zoomIn"
        static let zoomOut = "canvas.zoomOut"
        static let zoomToFit = "canvas.zoomToFit"
        /// The zoom level; its value is the scale, such as "100%".
        static let actualSize = "canvas.actualSize"
        /// The field of a callout bubble open for typing (FR-ORG-30).
        static let calloutField = "canvas.calloutField"
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

    enum Task {
        static let isTask = "task.isTask"
        static let done = "task.done"
        static let priority = "task.priority"
        static let overdue = "task.overdue"
        static let checkbox = "task.checkbox"
    }

    enum Chat {
        static let panel = "chat.panel"
        static let field = "chat.field"
        static let send = "chat.send"
        static let stop = "chat.stop"
        static let answer = "chat.answer"
        static let citation = "chat.citation"
        static let toolbar = "chat.toolbar"
        static let scope = "chat.scope"
        static let suggestion = "chat.suggestion"
        static let answerScope = "chat.answerScope"
        static let copy = "chat.copy"
        static let addToNote = "chat.addToNote"
        static let askAgain = "chat.askAgain"
        static let microphone = "chat.microphone"
        static let cancelVoice = "chat.cancelVoice"
    }

    /// Ask across the library (MM-52). Inside the panel the controls keep
    /// the `Chat` identifiers, so one page object reads both panels.
    enum LibraryChat {
        static let panel = "libraryChat.panel"
        static let toolbar = "libraryChat.toolbar"
    }

    enum ScreenshotAI {
        static let menu = "screenshot.ai.menu"
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
        static let showPaywall = "settings.showPaywall"
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
        static let emptyRecentlyDeleted = "settings.data.emptyRecentlyDeleted"
        static let exportAllMaps = "settings.data.exportAll"
    }
}
