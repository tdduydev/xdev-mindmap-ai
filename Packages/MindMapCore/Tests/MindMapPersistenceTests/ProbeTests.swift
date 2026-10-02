import CoreData
import Foundation
import MindMapGraph
@testable import MindMapPersistence
import SwiftData
import Testing

@Suite struct Probe {
    @Test func remoteChange() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "p.store")
        let a = try PersistenceController.makeContainer(at: .file(url))
        let b = try PersistenceController.makeContainer(at: .file(url))
        let names: [Notification.Name] = [.NSPersistentStoreRemoteChange, ModelContext.didSave, .NSManagedObjectContextDidSave]
        let box = Box()
        var tokens: [any NSObjectProtocol] = []
        for n in names {
            tokens.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: nil) { note in
                let keys = note.userInfo?.keys.map { "\($0)" } ?? []
                box.add("\(n.rawValue) obj=\(String(describing: note.object)) info=\(keys)")
            })
        }
        let ctx = ModelContext(b)
        ctx.author = "ext"
        let r = MapRecord(mapID: UUID())
        ctx.insert(r)
        try ctx.save()
        try await Task.sleep(for: .seconds(1))
        box.add("---- repo write")
        let repo = SwiftDataMapRepository(modelContainer: a)
        try await repo.create(GraphState.newMap(title: "x"))
        try await Task.sleep(for: .seconds(1))
        for i in box.items { print("PROBE", i) }
        let h = try ModelContext(a).fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        for t in h {
            print("PROBE TX author=\(t.author ?? "nil") changes=\(t.changes.count) token=\(t.token)")
            for c in t.changes { print("PROBE   ", c) }
        }
        _ = tokens
    }
}

final class Box: @unchecked Sendable {
    let l = NSLock()
    var items: [String] = []
    func add(_ s: String) { l.lock(); items.append(s); l.unlock() }
}
