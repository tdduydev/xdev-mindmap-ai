import Foundation
import FoundationModels
import MindMapAICore

// What guided generation returns. These stay inside this module: the rest of
// the app sees only the plain values of MindMapAICore.
//
// The tree is a flat list with parent IDs because a flat array of small
// structs is the shape the on-device model fills most reliably; the translator
// checks the IDs afterwards. Each `.maximumCount` must match `AIProposalLimits`,
// since guides take literals only.

@Generable
struct GeneratedMindMap {
    @Guide(description: "A short title for the whole map")
    var title: String

    @Guide(description: "The topics of the map, each parent listed before its subtopics", .maximumCount(30))
    var topics: [GeneratedTreeTopic]
}

@Generable
struct GeneratedTreeTopic {
    @Guide(description: "A unique short ID such as t1")
    var temporaryID: String

    @Guide(description: "The temporaryID of the parent topic, or an empty string for a main topic")
    var parentTemporaryID: String

    @Guide(description: "A short topic title")
    var title: String
}

@Generable
struct GeneratedTopicList {
    @Guide(description: "Suggested topics", .maximumCount(12))
    var topics: [GeneratedTopic]
}

@Generable
struct GeneratedTopic {
    @Guide(description: "A short topic title")
    var title: String
}

@Generable
struct GeneratedRewrites {
    @Guide(description: "Alternative titles", .maximumCount(3))
    var titles: [String]
}

extension GeneratedMindMap {
    func proposal() -> AIProposal {
        AIProposal(
            feature: .generateMap,
            anchor: .root,
            suggestedMapTitle: title,
            topics: topics.map {
                ProposedTopic(temporaryID: $0.temporaryID, parentTemporaryID: $0.parentTemporaryID, title: $0.title)
            }
        )
    }
}

extension GeneratedTopicList {
    /// Flat suggestions under the anchor. The model may return more than asked
    /// for, up to the guide's cap, so the request's own limit is applied here.
    func proposal(for feature: AIFeature, anchor: ProposalAnchor, limit: Int) -> AIProposal {
        AIProposal(
            feature: feature,
            anchor: anchor,
            topics: topics.prefix(limit).enumerated().map { index, topic in
                ProposedTopic(temporaryID: "s\(index + 1)", title: topic.title)
            }
        )
    }
}
