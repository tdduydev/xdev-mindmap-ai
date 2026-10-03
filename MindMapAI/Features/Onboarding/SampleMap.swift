import Foundation
import MindMapDomain
import MindMapGraph

/// The same local sample powers first launch and the three App Store fixtures.
enum SampleMap {
    static func make(languageCode: String, now: Date = .now) throws -> GraphState {
        let language = languageCode.hasPrefix("vi") ? "vi" : languageCode.hasPrefix("ja") ? "ja" : "en"
        let title = UITestFixture.Title.showcase(language)
        let branches: [(String, [String])] = switch language {
        case "vi": [
            ("Khám phá", ["Phỏng vấn người dùng", "Nhu cầu chính", "Cơ hội mới"]),
            ("Thiết kế", ["Luồng trải nghiệm", "Bộ nhận diện", "Thử nghiệm mẫu"]),
            ("Ra mắt", ["Trang giới thiệu", "Thông điệp", "Cộng đồng"]),
            ("Đo lường", ["Phản hồi", "Mức độ gắn bó", "Bước tiếp theo"]),
        ]
        case "ja": [
            ("調査", ["ユーザーインタビュー", "主なニーズ", "新しい機会"]),
            ("デザイン", ["体験の流れ", "ビジュアルアイデンティティ", "プロトタイプのテスト"]),
            ("発売", ["ランディングページ", "メッセージ", "コミュニティ"]),
            ("効果測定", ["フィードバック", "エンゲージメント", "次のステップ"]),
        ]
        default: [
            ("Discover", ["User interviews", "Key needs", "New opportunities"]),
            ("Design", ["Experience flow", "Visual identity", "Prototype testing"]),
            ("Launch", ["Landing page", "Messaging", "Community"]),
            ("Measure", ["Feedback", "Engagement", "Next steps"]),
        ]
        }
        let state = GraphState.newMap(title: title, now: now)
        var engine = try GraphEngine(state: state, clock: { now })
        guard let root = state.map.rootNodeID else { return state }
        for (heading, children) in branches {
            let branch = NodeID()
            try engine.execute(AddNodeCommand(nodeID: branch, .child(of: root), title: heading))
            for child in children {
                try engine.execute(AddNodeCommand(.child(of: branch), title: child))
            }
        }
        return engine.state
    }
}
