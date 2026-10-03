import Foundation
import MindMapAICore

/// The model generations prompts are tuned for. Apple changed the on-device
/// model at 26.4 and 27.0 and advises re-evaluating prompts for each one.
public enum PromptVersion: String, Hashable, Sendable, CaseIterable {
    case v26_0 = "26.0"
    case v26_4 = "26.4"
    case v27_0 = "27.0"

    /// The generation the running OS ships.
    public static var current: PromptVersion {
        if #available(macOS 27.0, iOS 27.0, *) { return .v27_0 }
        if #available(macOS 26.4, iOS 26.4, *) { return .v26_4 }
        return .v26_0
    }
}

/// Every instruction and prompt the Apple provider sends, in one place.
///
/// Instructions are English and fixed per feature; the person's text only ever
/// goes in the prompt, never in the instructions, so it is treated as content
/// rather than as a rule for the model.
public struct PromptCatalog: Hashable, Sendable {
    public let version: PromptVersion

    public init(version: PromptVersion = .current) {
        self.version = version
    }

    // MARK: Instructions

    public func instructions(for feature: AIFeature, language: AILanguage, userLocaleIdentifier: String) -> String {
        [
            Self.commonRules(for: version),
            featureRules(for: feature),
            "The person's locale is \(userLocaleIdentifier).",
            "You MUST respond in \(language.englishName).",
        ].joined(separator: "\n")
    }

    /// One text for every generation until an evaluation shows a generation
    /// needs its own; add the case then, so older OS versions keep theirs.
    private static func commonRules(for version: PromptVersion) -> String {
        switch version {
        case .v26_0, .v26_4, .v27_0:
            """
            You help a person build a mind map: a tree of short topics around one central topic.
            A topic title is a short phrase of at most eight words, not a sentence.
            Keep names, technical terms and mixed Vietnamese and English wording exactly as the person wrote them.
            Never repeat a topic that is already in the map.
            """
        }
    }

    private func featureRules(for feature: AIFeature) -> String {
        switch feature {
        case .generateMap:
            """
            Create a mind map for the subject the person describes, with a short title.
            Give each topic a unique temporaryID such as t1, t2 and t3.
            A main topic has an empty parentTemporaryID; a subtopic names the temporaryID of its parent, listed before it.
            """
        case .expandTopic:
            "Suggest subtopics that belong directly under the focus topic."
        case .brainstorm:
            "Brainstorm varied ideas related to the focus topic. Mix practical and unexpected ideas."
        case .findMissingTopics:
            "Suggest topics the branch might be missing. Offer them as ideas to consider. Suggest fewer when the branch is already complete."
        case .rewrite:
            "Rewrite the title of the focus topic as asked. Keep its meaning."
        case .summarize:
            "Summarize the focus topic and its subtopics in plain sentences. Do not add facts that are not in the map."
        case .suggestTags:
            """
            Suggest tags that sort the listed topics: short labels of one or two words, such as a category, a status or an owner.
            When an existing tag fits, use its name exactly as written. Do not repeat a tag a topic already has.
            Give a topic no tag rather than a vague one.
            """
        case .suggestGroups:
            """
            Sort the listed topics into groups of related topics, and give each group a short title.
            A group holds two or more topics, by their references. A topic is in one group at most; leave a topic out when no group fits it.
            """
        case .summarizeBoundary:
            "Give the listed group of topics one short title that names what they have in common. Do not add facts that are not in the map."
        }
    }

    // MARK: Chat

    /// The chat's instructions (docs/chat.md): fixed, English, and holding no
    /// map content, which only ever arrives through the question and the tools.
    /// The answer language is in each prompt, since it follows each question.
    public func chatInstructions(userLocaleIdentifier: String) -> String {
        [
            Self.chatRules(for: version),
            "The person's locale is \(userLocaleIdentifier).",
        ].joined(separator: "\n")
    }

    private static func chatRules(for version: PromptVersion) -> String {
        switch version {
        case .v26_0, .v26_4, .v27_0:
            """
            You answer questions about the person's mind map, a tree of topics, using only what your tools return.
            Call searchTopics to find topics by words, readTopic to read one topic's note and subtopics, and readBranch to read the outline under a topic. Read the map before you answer.
            Tool results name topics with handles such as T1. After each fact, cite the topic it came from with its handle in brackets, for example [T1]. Only cite handles a tool returned.
            If the tools find nothing that answers the question, say so in the answer language. Never invent topics, facts or handles.
            Keep names, technical terms and mixed Vietnamese and English wording exactly as the person wrote them.
            Answer in a few sentences or a short list. You cannot change the map; say so if asked to.
            Stay on the person's maps: no persona, no small talk.
            """
        }
    }

    /// The question as the model sees it. The map title tells it what the
    /// tools read; the language line keeps the answer in the question's language.
    /// `branchTitle` is the branch the tools are limited to (MM-78); the
    /// answer says so, since it may miss what lies outside.
    public func chatPrompt(question: String, mapTitle: String, language: AILanguage, branchTitle: String? = nil) -> String {
        var lines = ["Map: \(mapTitle)"]
        if let branchTitle {
            lines.append("Scope: only the branch \u{201C}\(branchTitle.split(whereSeparator: \.isNewline).joined(separator: " "))\u{201D}. The tools read only this branch. Begin the answer by saying it covers this branch.")
        }
        lines.append("Question: \(question)")
        lines.append("You MUST respond in \(language.englishName).")
        return lines.joined(separator: "\n")
    }

    // MARK: Prompts

    public func prompt(for request: GenerateMapRequest) -> String {
        """
        Subject: \(request.prompt)
        Create a mind map with at most \(request.maximumTopics) topics and at most three levels.
        """
    }

    public func prompt(for request: ExpandTopicRequest) -> String {
        render(request.context) + "\nSuggest up to \(request.maximumTopics) new subtopics for the focus topic."
    }

    public func prompt(for request: BrainstormRequest) -> String {
        let question = request.question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let task = question.isEmpty
            ? "Brainstorm up to \(request.maximumTopics) ideas around the focus topic."
            : "Brainstorm up to \(request.maximumTopics) ideas for this question: \(question)"
        return render(request.context) + "\n" + task
    }

    public func prompt(for request: MissingTopicsRequest) -> String {
        render(request.context) + "\nSuggest up to \(request.maximumTopics) topics this branch might be missing."
    }

    public func prompt(for request: RewriteRequest) -> String {
        let task = switch request.style {
        case .shorter: "Make it shorter."
        case .clearer: "Make it clearer."
        case .formal: "Make it more formal."
        case .simpler: "Use simpler words."
        case .technical: "Use precise technical wording."
        case .vietnamese: "Translate it into Vietnamese."
        case .english: "Translate it into English."
        }
        return render(request.context)
            + "\nGive up to \(AIProposalLimits.maximumRewriteSuggestions) alternative titles for the focus topic. \(task)"
    }

    public func prompt(for request: SummarizeRequest) -> String {
        guard !request.partialSummaries.isEmpty else {
            return render(request.context) + "\nSummarize this branch in two to four sentences."
        }
        let parts = request.partialSummaries.map { "- \($0)" }.joined(separator: "\n")
        return render(request.context)
            + "\nThese are summaries of parts of the branch:\n\(parts)\nCombine them into one summary of two to four sentences."
    }

    public func prompt(for request: SuggestTagsRequest) -> String {
        var lines = ["Map: \(request.mapTitle)"]
        if !request.availableTags.isEmpty {
            lines.append("Existing tags: " + request.availableTags.joined(separator: "; "))
        }
        lines.append("Topics:")
        for topic in request.topics {
            var line = "- \(topic.reference): \(topic.title)"
            if !topic.path.isEmpty { line += " (under " + topic.path.joined(separator: " > ") + ")" }
            if !topic.tags.isEmpty { line += " [tags: " + topic.tags.joined(separator: "; ") + "]" }
            lines.append(line)
        }
        lines.append("Suggest up to \(AIProposalLimits.maximumTagsPerTopic) tags for each topic, by its reference.")
        return lines.joined(separator: "\n")
    }

    public func prompt(for request: SuggestGroupsRequest) -> String {
        var lines = ["Map: \(request.mapTitle)"]
        if !request.path.isEmpty { lines.append("Path: " + request.path.joined(separator: " > ")) }
        lines.append("Parent topic: \(request.parentTitle)")
        lines.append("Topics under it:")
        for child in request.children {
            lines.append("- \(child.reference): \(child.title)")
        }
        lines.append("Suggest up to \(AIProposalLimits.maximumSuggestedGroups) groups.")
        return lines.joined(separator: "\n")
    }

    public func prompt(for request: SummarizeBoundaryRequest) -> String {
        var lines = ["Map: \(request.mapTitle)", "Parent topic: \(request.parentTitle)", "Topics in the group:"]
        for line in request.outline {
            lines.append(String(repeating: "  ", count: line.depth) + "- " + line.title)
        }
        if request.omittedCount > 0 {
            lines.append("(\(request.omittedCount) more subtopics are not shown.)")
        }
        lines.append("Write a title for this group.")
        return lines.joined(separator: "\n")
    }

    /// The context as a short outline. Indented lines read better to the model
    /// than JSON and cost fewer tokens.
    func render(_ context: AIContext) -> String {
        var lines = ["Map: \(context.mapTitle)"]
        if !context.ancestors.isEmpty {
            lines.append("Path to the focus topic: " + context.ancestors.map(\.title).joined(separator: " > "))
        }
        lines.append("Focus topic: \(context.focus.title)")
        if let note = context.focus.note {
            lines.append("Note on the focus topic: \(note)")
        }
        if !context.descendants.isEmpty {
            lines.append("Existing subtopics:")
            for topic in context.descendants {
                let indent = String(repeating: "  ", count: max(0, topic.depth - 1))
                lines.append("\(indent)- \(topic.title)")
            }
        }
        if context.omittedDescendantCount > 0 {
            lines.append("(\(context.omittedDescendantCount) more subtopics are not shown.)")
        }
        if !context.siblings.isEmpty {
            lines.append("Topics beside the focus topic: " + context.siblings.map(\.title).joined(separator: "; "))
        }
        if !context.linkedTopics.isEmpty {
            lines.append("Topics linked to the focus topic: " + context.linkedTopics.map(\.title).joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}
