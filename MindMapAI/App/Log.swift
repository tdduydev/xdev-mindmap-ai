import OSLog

/// Loggers by area. Map content (titles, notes, prompts) is never logged;
/// anything that might contain it must be interpolated with `privacy: .private`.
enum Log {
    private static let subsystem = "asia.xdev.mindmapai"

    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let graph = Logger(subsystem: subsystem, category: "Graph")
    static let designSystem = Logger(subsystem: subsystem, category: "DesignSystem")
}
