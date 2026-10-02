import Foundation

/// One field of a command that sets several: leave it, or set it (to nil
/// too, which clears it). Lets one command cover Make Task, Mark as Done, a
/// priority key and a date without touching the other fields.
public enum FieldChange<Value: Hashable & Sendable>: Hashable, Sendable {
    case keep
    case set(Value)

    func apply(to value: inout Value) {
        if case .set(let newValue) = self { value = newValue }
    }

    func map<Other>(_ transform: (Value) throws -> Other) rethrows -> FieldChange<Other> {
        switch self {
        case .keep: .keep
        case .set(let value): .set(try transform(value))
        }
    }
}
