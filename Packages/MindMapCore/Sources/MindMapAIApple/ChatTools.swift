import Foundation
import FoundationModels
import MindMapAICore
import Synchronization

// The chat's tools for one map (docs/chat.md, Tools). Three, within the three
// to five Apple advises per request; `suggestTopics` joins them in MM-51.
// Each forwards to `ChatMapReader`, which holds the logic tests check.

/// Tells the conversation a tool ran: its name and the tokens its result costs.
final class ChatToolEvents: Sendable {
    private let handler = Mutex<(@Sendable (String, Int) -> Void)?>(nil)

    func observe(_ newHandler: (@Sendable (String, Int) -> Void)?) {
        handler.withLock { $0 = newHandler }
    }

    func report(_ toolName: String, output: String) {
        let current = handler.withLock { $0 }
        current?(toolName, TokenEstimator.estimate(output))
    }
}

@Generable
struct SearchTopicsArguments {
    @Guide(description: "A few words to look for in topic titles and notes")
    var query: String
}

@Generable
struct ReadTopicArguments {
    @Guide(description: "The handle of the topic, such as T3")
    var handle: String
}

@Generable
struct ReadBranchArguments {
    @Guide(description: "The handle of the topic to start from, such as T3, or an empty string for the whole map")
    var handle: String

    @Guide(description: "How many levels of subtopics to read", .range(1...3))
    var depth: Int
}

struct SearchTopicsTool: Tool {
    let name = "searchTopics"
    let description = "Finds topics in the map whose title or note contains the words. Returns handles, titles and paths."
    let reader: ChatMapReader
    let events: ChatToolEvents

    @concurrent
    func call(arguments: SearchTopicsArguments) async throws -> String {
        let output = await reader.searchTopics(arguments.query)
        events.report(name, output: output)
        return output
    }
}

struct ReadTopicTool: Tool {
    let name = "readTopic"
    let description = "Reads one topic by handle: its note, path, subtopics, tags, task state and links."
    let reader: ChatMapReader
    let events: ChatToolEvents

    @concurrent
    func call(arguments: ReadTopicArguments) async throws -> String {
        let output = await reader.readTopic(arguments.handle)
        events.report(name, output: output)
        return output
    }
}

struct ReadBranchTool: Tool {
    let name = "readBranch"
    let description = "Reads the outline under a topic, with handles and notes, a few levels deep."
    let reader: ChatMapReader
    let events: ChatToolEvents

    @concurrent
    func call(arguments: ReadBranchArguments) async throws -> String {
        let output = await reader.readBranch(arguments.handle, depth: arguments.depth)
        events.report(name, output: output)
        return output
    }
}
