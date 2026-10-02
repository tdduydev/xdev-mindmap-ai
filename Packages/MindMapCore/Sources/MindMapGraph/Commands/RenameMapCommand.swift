import Foundation
import MindMapDomain

/// Renames the map itself. A command, like any other edit, so it is one undo
/// step and is saved by the open editor instead of racing it from elsewhere.
/// The central topic keeps its own title.
public struct RenameMapCommand: GraphCommand {
    public let title: String

    public init(title: String) {
        self.title = title
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        transaction.updateMap { $0.title = title }
    }
}
