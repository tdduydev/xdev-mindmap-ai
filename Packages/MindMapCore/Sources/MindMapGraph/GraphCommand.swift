import Foundation
import MindMapDomain

/// A change to a graph. Every mutation, from a key press, an import or an
/// accepted AI proposal, is a command, so all of them get the same validation,
/// undo and persistence path.
///
/// A command only describes the change. It does not supply its own inverse:
/// the engine records what the command touched and undoes by replaying the old
/// values (see `GraphChangeSet`).
public protocol GraphCommand: Sendable {
    func execute(in transaction: inout GraphTransaction) throws
}

/// Runs several commands as one undo step. If any of them throws, none apply.
public struct BatchCommand: GraphCommand {
    public let commands: [any GraphCommand]

    public init(_ commands: [any GraphCommand]) {
        self.commands = commands
    }

    public func execute(in transaction: inout GraphTransaction) throws {
        for command in commands {
            try command.execute(in: &transaction)
        }
    }
}
