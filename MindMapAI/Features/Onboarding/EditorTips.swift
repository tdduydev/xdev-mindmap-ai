import SwiftUI
import TipKit

/// Tips live on the controls they explain and stop after the first display or
/// first use. TipKit owns display history across launches.
enum EditorTips {
    static let addTopic = AddTopic()
    static let ai = AI()
    static let chat = Chat()
    static let find = Find()

    struct AddTopic: Tip {
        var title: Text { Text("Add a Topic") }
        var message: Text? { Text("Select a topic, then add a child to grow this branch.") }
        var image: Image? { Image(systemName: "arrow.turn.down.right") }
        var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
    }

    struct AI: Tip {
        var title: Text { Text("Get Ideas with AI") }
        var message: Text? { Text("Ask on-device AI for suggestions you can review before adding.") }
        var image: Image? { Image(systemName: "sparkles") }
        var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
    }

    struct Chat: Tip {
        var title: Text { Text("Ask About This Map") }
        var message: Text? { Text("Ask a question and jump to the topics behind the answer.") }
        var image: Image? { Image(systemName: "bubble.left.and.text.bubble.right") }
        var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
    }

    struct Find: Tip {
        var title: Text { Text("Find a Topic") }
        var message: Text? { Text("Search this map and jump between matching topics.") }
        var image: Image? { Image(systemName: "magnifyingglass") }
        var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
    }
}
