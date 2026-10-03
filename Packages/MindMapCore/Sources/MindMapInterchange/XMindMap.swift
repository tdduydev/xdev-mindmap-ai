import Foundation
import MindMapDomain
import MindMapGraph
import MindMapImages

/// XMind files (`.xmind`, MM-103, FR-IO-11): a ZIP archive holding
/// `content.json` (XMind 2020 and later, XMind Zen) or `content.xml` (XMind 8
/// and earlier), plus pictures and attachments.
///
/// Sources for the layout, since XMind publishes no formal specification:
/// the `xmind` SDK (github.com/xmindltd/xmind-sdk-js, the JSON model) and the
/// XMind 8 file format notes (github.com/xmindltd/xmind/wiki/XMindFileFormat,
/// the `xmap-content` XML). The test fixtures are written from those, not
/// copied from files made by the app.
///
/// Each sheet becomes a map. Topics keep their tree; plain notes, labels
/// (as tags), web links, relationships (as connections), detached topics (as
/// floating topics), summaries, boundaries, callouts, priority and task
/// markers and pictures carry over. What does not is counted in the report.
public enum XMindMap {
    /// One sheet as read from the file, before it is a map. Topics are flat
    /// with indexes for children, so walking a deep file costs no stack;
    /// `topics[0]` is the sheet's root topic.
    public struct Sheet: Hashable, Sendable {
        public var title: String
        public var topics: [Topic]
        public var relationships: [Relationship]
    }

    public struct Topic: Hashable, Sendable {
        /// The file's own ID, for relationships, summaries and `xmind:#` links.
        public var fileID: String?
        public var title = ""
        public var note: String?
        public var labels: [String] = []
        public var href: String?
        /// The picture's path inside the archive.
        public var imagePath: String?
        public var markers: [String] = []
        public var position: TopicPosition?
        public var attached: [Int] = []
        public var detached: [Int] = []
        /// Topics that stand for a summary bracket, named by `summaries`.
        public var summaryTopics: [Int] = []
        public var callouts: [Int] = []
        public var summaries: [Run] = []
        public var boundaries: [Run] = []
    }

    /// A summary or boundary over attached children.
    public struct Run: Hashable, Sendable {
        /// `(first,last)` indexes into the attached children, or "master" for the topic itself.
        public var range: String
        public var title: String?
        /// The summary's topic.
        public var topicID: String?
    }

    public struct Relationship: Hashable, Sendable {
        public var end1: String
        public var end2: String
        public var title: String?
    }

    /// Reads the archive into sheets and the pictures their topics name.
    public static func read(
        _ data: Data,
        fileName: String,
        limits: ZipLimits = .standard,
        now: Date = .now
    ) throws(ForeignImportError) -> ForeignImport {
        var archive: ZipArchive
        do {
            archive = try ZipArchive(data, limits: limits.archiveLimits)
        } catch {
            throw foreignError(error)
        }
        let sheets: [Sheet]
        do {
            // XMind 2020 also writes a content.xml that only says to update
            // the app, so the JSON wins when both are there.
            if let json = try archive.read("content.json") {
                sheets = try parseJSON(json)
            } else if let xml = try archive.read("content.xml") {
                sheets = try parseXML(xml)
            } else {
                throw ForeignImportError.wrongFormat
            }
        } catch let error as ForeignImportError {
            throw error
        } catch let error as ZipArchive.Error {
            throw foreignError(error)
        } catch {
            throw .damaged
        }

        var result = ForeignImport(maps: [])
        for sheet in sheets where !sheet.topics.isEmpty {
            let images = pictures(of: sheet, in: &archive, report: &result.report)
            let built = try graph(from: sheet, images: images, fileName: fileName, now: now)
            result.maps.append(built.map)
            result.report.merge(built.report)
            for image in images.values {
                if let bytes = image.data, built.map.images[image.id] != nil {
                    result.imageData[image.id] = bytes
                }
            }
        }
        guard !result.maps.isEmpty else { throw .emptyDocument }
        return result
    }

    private static func foreignError(_ error: ZipArchive.Error) -> ForeignImportError {
        switch error {
        // An `.xmind` file that is no ZIP at all is not an XMind file.
        case .notAnArchive: .wrongFormat
        case .damaged: .damaged
        case .tooLarge: .tooLarge
        }
    }

    /// The limits `read` puts on the archive, public so tests can make them small.
    public struct ZipLimits: Hashable, Sendable {
        public var maximumEntrySize: Int
        public var maximumTotalSize: Int

        public init(maximumEntrySize: Int, maximumTotalSize: Int) {
            self.maximumEntrySize = maximumEntrySize
            self.maximumTotalSize = maximumTotalSize
        }

        public static let standard = ZipLimits(
            maximumEntrySize: ZipArchive.Limits.standard.maximumEntrySize,
            maximumTotalSize: ZipArchive.Limits.standard.maximumTotalSize
        )

        var archiveLimits: ZipArchive.Limits {
            ZipArchive.Limits(
                maximumEntrySize: maximumEntrySize,
                maximumTotalSize: maximumTotalSize,
                maximumEntryCount: ZipArchive.Limits.standard.maximumEntryCount
            )
        }
    }

    // MARK: Pictures

    /// Each topic's picture, read from the archive and scaled the way a
    /// picture added by hand is (`ImageProcessor`, MM-63). One that is
    /// missing or cannot be decoded is counted, not fatal.
    private static func pictures(
        of sheet: Sheet,
        in archive: inout ZipArchive,
        report: inout ImportReport
    ) -> [Int: MindImage] {
        var images: [Int: MindImage] = [:]
        for (index, topic) in sheet.topics.enumerated() {
            guard let path = topic.imagePath else { continue }
            guard let bytes = try? archive.read(path),
                  let processed = try? ImageProcessor.standard.processSynchronously(bytes)
            else {
                report.record(.image)
                continue
            }
            // The map and node IDs are set when the graph is built.
            images[index] = processed.image(mapID: MapID(), nodeID: NodeID())
        }
        return images
    }

    // MARK: Building the map

    /// The sheet as a new map, built through `GraphEngine` in one step.
    ///
    /// Each optional piece (a summary, boundary, connection, link) is first
    /// tried on a scratch transaction; only those that hold are kept, so one
    /// odd bracket in the file costs that bracket, not the whole map.
    static func graph(
        from sheet: Sheet,
        images: [Int: MindImage] = [:],
        fileName: String,
        now: Date
    ) throws(ForeignImportError) -> (map: GraphState, report: ImportReport) {
        let root = sheet.topics[0]
        let mapTitle = [root.title, sheet.title, fileName].first { !$0.allSatisfy(\.isWhitespace) } ?? fileName
        let mapID = MapID()
        let initial = GraphState(map: MindMap(id: mapID, title: mapTitle, createdAt: now))
        var planner = Planner(sheet: sheet, images: images, mapID: mapID, transaction: GraphTransaction(state: initial, now: now))
        planner.plan()
        do {
            var engine = try GraphEngine(state: initial, clock: { now })
            try engine.execute(BatchCommand(planner.commands))
            return (engine.state, planner.report)
        } catch {
            // The plan was checked step by step, so this is a bug, not the file.
            throw .damaged
        }
    }

    private struct Planner {
        let sheet: Sheet
        let images: [Int: MindImage]
        let mapID: MapID
        var transaction: GraphTransaction
        var commands: [any GraphCommand] = []
        var report = ImportReport()
        let ids: [NodeID]
        let indexByFileID: [String: Int]
        /// Summaries and boundaries wait until every topic they span is in.
        private var pendingRuns: [Int] = []
        /// Topics by tag, tagged once per tag at the end: one command per
        /// topic would scan every tag link each time.
        private var tagged: [String: (name: String, nodeIDs: [NodeID])] = [:]
        private var tagOrder: [String] = []

        init(sheet: Sheet, images: [Int: MindImage], mapID: MapID, transaction: GraphTransaction) {
            self.sheet = sheet
            self.images = images
            self.mapID = mapID
            self.transaction = transaction
            ids = sheet.topics.map { _ in NodeID() }
            var byFileID: [String: Int] = [:]
            for (index, topic) in sheet.topics.enumerated() {
                if let id = topic.fileID, byFileID[id] == nil { byFileID[id] = index }
            }
            indexByFileID = byFileID
        }

        mutating func plan() {
            let metadata = NodeMetadata(origin: .imported)
            let root = sheet.topics[0]
            require(AddNodeCommand(nodeID: ids[0], .root, title: root.title, note: note(of: 0), metadata: metadata))
            addBranch(from: 0)

            for (offset, index) in root.detached.enumerated() {
                addFloating(index, offset: offset)
            }
            // Detached topics anywhere else: XMind keeps them on the root, but
            // a hand-edited file may not, and a topic is never dropped.
            var floatingOffset = root.detached.count
            for (index, topic) in sheet.topics.enumerated() where index != 0 {
                for detached in topic.detached {
                    addFloating(detached, offset: floatingOffset)
                    floatingOffset += 1
                }
            }

            var next = 0
            while next < pendingRuns.count {
                addRuns(of: pendingRuns[next])
                next += 1
            }
            for key in tagOrder {
                guard let tag = tagged[key] else { continue }
                require(TagNodesCommand(nodeIDs: tag.nodeIDs, add: [.named(tag.name)], origin: .imported))
            }
            addRelationships()
        }

        // MARK: Topics

        private mutating func addFloating(_ index: Int, offset: Int) {
            // Spread out below the root when the file gives no position.
            let position = sheet.topics[index].position ?? TopicPosition(x: 0, y: 240 + Double(offset) * 80)
            require(AddFloatingTopicCommand(
                nodeID: ids[index],
                title: sheet.topics[index].title,
                position: position,
                metadata: NodeMetadata(origin: .imported)
            ))
            if let note = note(of: index) {
                require(UpdateNodeCommand(nodeID: ids[index], .note(note)))
            }
            addBranch(from: index)
        }

        /// Adds every attached child under `top`, depth first with a stack,
        /// then the attributes of each topic added.
        private mutating func addBranch(from top: Int) {
            addAttributes(of: top)
            var stack = [top]
            while let parent = stack.popLast() {
                let topic = sheet.topics[parent]
                for child in topic.attached + calloutChildren(of: parent) {
                    require(AddNodeCommand(
                        nodeID: ids[child],
                        .child(of: ids[parent]),
                        title: sheet.topics[child].title,
                        note: note(of: child),
                        metadata: NodeMetadata(origin: .imported)
                    ))
                    addAttributes(of: child)
                }
                if !topic.summaries.isEmpty || !topic.boundaries.isEmpty || !topic.summaryTopics.isEmpty {
                    pendingRuns.append(parent)
                }
                // Reversed so the first child's branch is added first.
                stack.append(contentsOf: (topic.attached + calloutChildren(of: parent)).reversed())
            }
        }

        /// A callout that is only a line of text becomes the topic's callout
        /// (the first one; the app has one per topic). One with children,
        /// a note or anything else stays a topic, so nothing is lost.
        private func calloutChildren(of index: Int) -> [Int] {
            let callouts = sheet.topics[index].callouts
            guard let first = callouts.first, isPlainCallout(first) else { return callouts }
            return Array(callouts.dropFirst())
        }

        private func isPlainCallout(_ index: Int) -> Bool {
            let topic = sheet.topics[index]
            return topic.attached.isEmpty && topic.detached.isEmpty && topic.callouts.isEmpty
                && topic.summaryTopics.isEmpty && topic.note == nil && topic.labels.isEmpty && topic.href == nil
                && topic.imagePath == nil && topic.markers.isEmpty
                && MindNode.normalizedCallout(topic.title) != nil
        }

        private mutating func addAttributes(of index: Int) {
            let topic = sheet.topics[index]
            let id = ids[index]
            if let first = topic.callouts.first, isPlainCallout(first) {
                require(SetCalloutCommand(nodeIDs: [id], text: sheet.topics[first].title))
            }
            for name in topic.labels.compactMap(MindTag.normalizedName) {
                let key = MindTag.key(for: name)
                if tagged[key] == nil { tagOrder.append(key) }
                tagged[key, default: (name, [])].nodeIDs.append(id)
            }
            if let href = topic.href {
                if let link = TopicLink.normalized(href), link.url != nil {
                    require(SetNodeLinkCommand(nodeIDs: [id], link: link))
                } else if href.lowercased().hasPrefix("xap:") {
                    report.record(.attachment)
                }
                // `xmind:#id` links are added with the relationships; anything else is in the note.
            }
            var priority: TaskPriority?
            var task: TaskState?
            for marker in topic.markers {
                if let level = Self.priority(marker) {
                    priority = priority ?? level
                } else if let state = Self.taskState(marker) {
                    task = task ?? state
                } else {
                    report.record(.icon)
                }
            }
            if priority != nil || task != nil {
                require(SetTaskCommand(
                    nodeIDs: [id],
                    state: task.map { .set($0) } ?? .keep,
                    priority: priority.map { .set($0) } ?? .keep
                ))
            }
            if var image = images[index] {
                image = MindImage(
                    id: image.id, mapID: mapID, nodeID: id, data: image.data, uniformType: image.uniformType,
                    pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, byteCount: image.byteCount
                )
                if !attempt(SetNodeImageCommand(nodeID: id, image: image)) { report.record(.image) }
            }
        }

        /// The topic's plain note, with what has no field of its own: labels
        /// too long for a tag and a link this build does not open.
        private func note(of index: Int) -> String? {
            let topic = sheet.topics[index]
            var parts: [String] = []
            if let note = topic.note, !note.allSatisfy(\.isWhitespace) { parts.append(note) }
            for label in topic.labels where MindTag.normalizedName(label) == nil && !label.allSatisfy(\.isWhitespace) {
                parts.append(label)
            }
            if let href = topic.href, !href.allSatisfy(\.isWhitespace), TopicLink.normalized(href)?.url == nil,
               !href.lowercased().hasPrefix("xap:"), Self.topicLinkTarget(href) == nil {
                parts.append(href)
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }

        // MARK: Summaries and boundaries

        private mutating func addRuns(of index: Int) {
            let topic = sheet.topics[index]
            var placed: Set<Int> = []
            for run in topic.summaries {
                guard let topicID = run.topicID, let summary = indexByFileID[topicID],
                      topic.summaryTopics.contains(summary), !placed.contains(summary)
                else {
                    report.record(.summary)
                    continue
                }
                placed.insert(summary)
                let ends = self.ends(of: run, in: index)
                if let ends, AddSummaryCommand.canSummarize(from: ids[ends.first], to: ids[ends.last], in: transaction.state),
                   attempt(AddSummaryCommand(
                       nodeID: ids[summary], from: ids[ends.first], to: ids[ends.last], title: sheet.topics[summary].title
                   ))
                {
                    var changes: [NodeAttributeChange] = [.metadata(NodeMetadata(origin: .imported))]
                    if let note = note(of: summary) { changes.append(.note(note)) }
                    require(UpdateNodeCommand(nodeID: ids[summary], changes: changes))
                    addBranch(from: summary)
                } else {
                    addPlainSummaryTopic(summary, under: index)
                }
            }
            // A summary topic no bracket names is still a topic.
            for summary in topic.summaryTopics where !placed.contains(summary) {
                placed.insert(summary)
                addPlainSummaryTopic(summary, under: index)
            }
            for run in topic.boundaries {
                let added: Bool
                if run.range == "master" {
                    // The whole topic: a boundary around it alone, under its parent.
                    added = attempt(AddGroupCommand(from: ids[index], title: run.title, origin: .imported))
                } else if let ends = ends(of: run, in: index) {
                    added = attempt(AddGroupCommand(from: ids[ends.first], to: ids[ends.last], title: run.title, origin: .imported))
                } else {
                    added = false
                }
                if !added { report.record(.boundary) }
            }
        }

        /// A summary whose bracket does not fit stays as the last child, so its
        /// text and branch are kept; the bracket is counted as lost.
        private mutating func addPlainSummaryTopic(_ summary: Int, under parent: Int) {
            report.record(.summary)
            require(AddNodeCommand(
                nodeID: ids[summary],
                .child(of: ids[parent]),
                title: sheet.topics[summary].title,
                note: note(of: summary),
                metadata: NodeMetadata(origin: .imported)
            ))
            addBranch(from: summary)
        }

        private func ends(of run: Run, in index: Int) -> (first: Int, last: Int)? {
            let attached = sheet.topics[index].attached
            guard let range = Self.range(run.range), range.first >= 0, range.last < attached.count else { return nil }
            return (attached[range.first], attached[range.last])
        }

        // MARK: Connections

        private mutating func addRelationships() {
            for relationship in sheet.relationships {
                guard let source = indexByFileID[relationship.end1], let target = indexByFileID[relationship.end2],
                      attempt(ConnectNodesCommand(from: ids[source], to: ids[target], label: relationship.title))
                else {
                    report.record(.connection)
                    continue
                }
            }
            // A link to another topic of the file is a connection, as in FreeMind.
            for (index, topic) in sheet.topics.enumerated() {
                guard let href = topic.href, let targetID = Self.topicLinkTarget(href) else { continue }
                guard let target = indexByFileID[targetID],
                      attempt(ConnectNodesCommand(from: ids[index], to: ids[target]))
                else {
                    report.record(.connection)
                    continue
                }
            }
        }

        // MARK: Running commands

        /// A step that cannot fail on a well-formed plan (a topic under a topic
        /// already added). If it does, the step is skipped, never the map.
        private mutating func require(_ command: any GraphCommand) {
            _ = attempt(command)
        }

        /// Runs the command on a copy and keeps it only if it worked, so a
        /// command that throws half way leaves nothing behind.
        private mutating func attempt(_ command: any GraphCommand) -> Bool {
            var probe = transaction
            do {
                try command.execute(in: &probe)
            } catch {
                return false
            }
            transaction = probe
            commands.append(command)
            return true
        }

        // MARK: Markers

        /// XMind's `priority-1`… markers; 1 is the highest, as in the app.
        static func priority(_ marker: String) -> TaskPriority? {
            guard marker.hasPrefix("priority-"), let level = Int(marker.dropFirst("priority-".count)), level > 0 else {
                return nil
            }
            return TaskPriority(rawValue: min(level, 3))
        }

        /// XMind's progress markers: `task-done` is done, the rest (`task-start`,
        /// `task-quarter`, `task-half`…) an open task.
        static func taskState(_ marker: String) -> TaskState? {
            guard marker.hasPrefix("task-") else { return nil }
            return marker == "task-done" ? .done : .open
        }

        static func topicLinkTarget(_ href: String) -> String? {
            guard href.hasPrefix("xmind:#") else { return nil }
            let id = String(href.dropFirst("xmind:#".count))
            return id.isEmpty ? nil : id
        }

        static func range(_ text: String) -> (first: Int, last: Int)? {
            let digits = text.trimmingCharacters(in: CharacterSet(charactersIn: "()[] "))
            let parts = digits.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, let first = parts[0], let last = parts[1] else { return nil }
            return (min(first, last), max(first, last))
        }
    }
}

// MARK: - content.json

extension XMindMap {
    static func parseJSON(_ data: Data) throws(ForeignImportError) -> [Sheet] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw .damaged
        }
        guard let sheets = object as? [[String: Any]] else { throw .wrongFormat }
        return sheets.compactMap(sheet)
    }

    private static func sheet(_ json: [String: Any]) -> Sheet? {
        guard let rootJSON = json["rootTopic"] as? [String: Any] else { return nil }
        var topics = [topic(rootJSON)]
        // Index and JSON of topics whose children are still to be read.
        var stack: [(Int, [String: Any])] = [(0, rootJSON)]
        while let (index, json) = stack.popLast() {
            let children = json["children"] as? [String: Any] ?? [:]
            for (key, path) in [
                ("attached", \Topic.attached), ("detached", \Topic.detached),
                ("summary", \Topic.summaryTopics), ("callout", \Topic.callouts),
            ] as [(String, WritableKeyPath<Topic, [Int]>)] {
                for childJSON in children[key] as? [[String: Any]] ?? [] {
                    topics.append(topic(childJSON))
                    topics[index][keyPath: path].append(topics.count - 1)
                    stack.append((topics.count - 1, childJSON))
                }
            }
        }
        let relationships = (json["relationships"] as? [[String: Any]] ?? []).compactMap { json -> Relationship? in
            guard let end1 = json["end1Id"] as? String, let end2 = json["end2Id"] as? String else { return nil }
            return Relationship(end1: end1, end2: end2, title: json["title"] as? String)
        }
        return Sheet(title: json["title"] as? String ?? "", topics: topics, relationships: relationships)
    }

    private static func topic(_ json: [String: Any]) -> Topic {
        var topic = Topic()
        topic.fileID = json["id"] as? String
        topic.title = json["title"] as? String ?? ""
        let notes = json["notes"] as? [String: Any]
        topic.note = (notes?["plain"] as? [String: Any])?["content"] as? String
        topic.labels = json["labels"] as? [String] ?? []
        topic.href = json["href"] as? String
        if let source = (json["image"] as? [String: Any])?["src"] as? String {
            topic.imagePath = archivePath(source)
        }
        topic.markers = (json["markers"] as? [[String: Any]] ?? []).compactMap { $0["markerId"] as? String }
        if let position = json["position"] as? [String: Any],
           let x = (position["x"] as? NSNumber)?.doubleValue, let y = (position["y"] as? NSNumber)?.doubleValue
        {
            topic.position = TopicPosition(x: x, y: y)
        }
        topic.summaries = (json["summaries"] as? [[String: Any]] ?? []).compactMap { json in
            (json["range"] as? String).map { Run(range: $0, topicID: json["topicId"] as? String) }
        }
        topic.boundaries = (json["boundaries"] as? [[String: Any]] ?? []).compactMap { json in
            (json["range"] as? String).map { Run(range: $0, title: json["title"] as? String) }
        }
        return topic
    }

    /// `xap:resources/a.png` names `resources/a.png` in the archive.
    static func archivePath(_ source: String) -> String? {
        guard source.lowercased().hasPrefix("xap:") else { return nil }
        let path = String(source.dropFirst(4))
        return path.isEmpty ? nil : path
    }
}

// MARK: - content.xml

extension XMindMap {
    static func parseXML(_ data: Data) throws(ForeignImportError) -> [Sheet] {
        let reader = XMindXMLReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        // A map file has no business loading anything from outside itself.
        parser.shouldResolveExternalEntities = false
        let parsed = parser.parse()
        if reader.isWrongFormat { throw .wrongFormat }
        guard parsed else { throw .damaged }
        return reader.sheets
    }
}

/// Streams XMind 8's `content.xml`: `xmap-content` › `sheet` › `topic`, each
/// topic with `title`, `notes/plain`, `labels/label`, `marker-refs`,
/// `xhtml:img`, `position`, `children/topics[@type]`, `boundaries` and
/// `summaries`; relationships at the end of the sheet. Prefixes are matched
/// by local name, since files differ in what they declare.
private final class XMindXMLReader: NSObject, XMLParserDelegate {
    private(set) var sheets: [XMindMap.Sheet] = []
    private(set) var isWrongFormat = false

    private var sawRoot = false
    private var path: [String] = []
    private var sheet: XMindMap.Sheet?
    /// The topic each open `topic` element is, innermost last.
    private var topicStack: [Int] = []
    /// Whether each open `topic` element pushed onto `topicStack`; one in an
    /// unexpected place is skipped and must not pop its owner.
    private var topicPushed: [Bool] = []
    /// The `type` of each open `topics` element.
    private var listTypes: [String] = []
    private var text: String?
    private var relationship: XMindMap.Relationship?
    private var boundaryOwner: Int?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        let name = localName(elementName)
        let parent = path.last
        defer { path.append(name) }
        guard sawRoot else {
            sawRoot = true
            if name != "xmap-content" {
                isWrongFormat = true
                parser.abortParsing()
            }
            return
        }
        let attributes = Dictionary(attributes.map { (localName($0.key), $0.value) }) { first, _ in first }
        let pushedBefore = topicPushed.count

        switch name {
        case "sheet" where parent == "xmap-content":
            sheet = XMindMap.Sheet(title: "", topics: [], relationships: [])
        case "topic" where parent == "sheet" && sheet?.topics.isEmpty == true:
            startTopic(attributes)
        case "topic" where parent == "topics" && path.dropLast().last == "children" && currentTopic != nil:
            let owner = currentTopic!
            let type = listTypes.last ?? "attached"
            let index = startTopic(attributes)
            switch type {
            case "detached": sheet?.topics[owner].detached.append(index)
            case "summary": sheet?.topics[owner].summaryTopics.append(index)
            case "callout": sheet?.topics[owner].callouts.append(index)
            default: sheet?.topics[owner].attached.append(index)
            }
        case "topics" where parent == "children":
            listTypes.append(attributes["type"] ?? "attached")
        case "title" where parent == "topic" || parent == "sheet" || parent == "relationship" || parent == "boundary":
            text = ""
        case "plain" where parent == "notes":
            text = ""
        case "label" where parent == "labels":
            text = ""
        case "marker-ref":
            if let id = attributes["marker-id"], let topic = currentTopic { sheet?.topics[topic].markers.append(id) }
        case "img" where parent == "topic":
            if let source = attributes["src"], let topic = currentTopic {
                sheet?.topics[topic].imagePath = XMindMap.archivePath(source)
            }
        case "position" where parent == "topic":
            if let topic = currentTopic, let x = attributes["x"].flatMap(Double.init), let y = attributes["y"].flatMap(Double.init) {
                sheet?.topics[topic].position = TopicPosition(x: x, y: y)
            }
        case "boundary":
            boundaryOwner = currentTopic
            if let owner = boundaryOwner, let range = attributes["range"] {
                sheet?.topics[owner].boundaries.append(XMindMap.Run(range: range))
            } else {
                boundaryOwner = nil
            }
        case "summary" where parent == "summaries":
            if let topic = currentTopic, let range = attributes["range"] {
                sheet?.topics[topic].summaries.append(XMindMap.Run(range: range, topicID: attributes["topic-id"]))
            }
        case "relationship":
            if let end1 = attributes["end1"], let end2 = attributes["end2"] {
                relationship = XMindMap.Relationship(end1: end1, end2: end2)
            }
        default:
            break
        }
        if name == "topic", topicPushed.count == pushedBefore {
            topicPushed.append(false)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = localName(elementName)
        path.removeLast()
        let parent = path.last
        switch name {
        case "sheet" where parent == "xmap-content":
            if let sheet { sheets.append(sheet) }
            sheet = nil
        case "topic":
            if topicPushed.popLast() == true { topicStack.removeLast() }
        case "topics" where parent == "children":
            listTypes.removeLast()
        case "title":
            guard let value = text else { return }
            text = nil
            if parent == "topic", let topic = currentTopic {
                sheet?.topics[topic].title = value
            } else if parent == "sheet" {
                sheet?.title = value
            } else if parent == "relationship" {
                relationship?.title = value
            } else if parent == "boundary", let owner = boundaryOwner {
                let last = (sheet?.topics[owner].boundaries.count ?? 1) - 1
                sheet?.topics[owner].boundaries[last].title = value
            }
        case "plain":
            if let value = text, let topic = currentTopic { sheet?.topics[topic].note = value }
            text = nil
        case "label":
            if let value = text, let topic = currentTopic {
                // XMind 8 also writes several labels as one comma-separated label.
                let labels = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                sheet?.topics[topic].labels += labels
            }
            text = nil
        case "boundary":
            boundaryOwner = nil
        case "relationship":
            if let relationship { sheet?.relationships.append(relationship) }
            relationship = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text? += string
    }

    /// The innermost topic being read, nil inside a `topic` element that was skipped.
    private var currentTopic: Int? {
        topicPushed.last == true ? topicStack.last : nil
    }

    @discardableResult
    private func startTopic(_ attributes: [String: String]) -> Int {
        var topic = XMindMap.Topic()
        topic.fileID = attributes["id"]
        topic.href = attributes["href"]
        sheet?.topics.append(topic)
        let index = (sheet?.topics.count ?? 1) - 1
        topicStack.append(index)
        topicPushed.append(true)
        return index
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}
