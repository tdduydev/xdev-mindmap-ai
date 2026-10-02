import Foundation
import MindMapDomain

/// Picks the map's theme. A command so the choice is one undo step ("Change
/// Theme") and is saved with the map like any other edit (FR-THM-01).
public struct ChangeThemeCommand: GraphCommand {
    public let theme: MindMapTheme

    public init(theme: MindMapTheme) {
        self.theme = theme
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        transaction.updateMap { $0.theme = theme }
    }
}
