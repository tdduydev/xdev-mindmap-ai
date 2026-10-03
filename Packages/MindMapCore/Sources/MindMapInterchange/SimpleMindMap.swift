import Foundation
import MindMapDomain
import MindMapGraph

/// SimpleMind maps (`.smmx`, FR-IO-12, spike MM-104).
///
/// ModelMaker Tools publishes no specification. The layout below was read from
/// files SimpleMind for Windows 1.25 and 1.28 saved (`doc-version="3"`), public
/// on GitHub: `hervegirod/jSimpleMind/samples/mindmap.xml` and the tests of
/// `bsp2/tks` (`tks-projects/tools/org/tests/*/document/mindmap.xml`).
///
/// An `.smmx` file is a ZIP holding `document/mindmap.xml`:
/// `<simplemind-mindmaps><mindmap><meta>…<main-centraltheme id="0"/></meta>
/// <topics><topic id parent text …/></topics><relations>…</relations>`.
/// Topics are a flat list: `parent="-1"` is the central theme or a floating
/// topic, any other value the `id` of the parent. In `text`, `\N` is a line break.
///
/// Reading, per topic: `text` as the title, `<note>` as the note,
/// `<link urllink>` with a web or mail URL as the link (anything else into
/// the note), `checkbox="True"` as a task (`checked="True"` done),
/// `collapsed="True"` folds it, the topic's own `strokecolor` by hue.
/// `<relation source target>` becomes a Connection, labelled by its first
/// text child. Pictures are counted. A floating topic (a second
/// `parent="-1"`) goes under the central topic, since the file's canvas
/// coordinates do not say where it sits relative to the layout the app draws.
public enum SimpleMindMap {
    static let documentPath = "document/mindmap.xml"

    @concurrent
    public static func read(_ data: Data, fileName: String, now: Date = .now) async throws(ForeignImportError) -> ForeignImport {
        let xml: Data
        do {
            var archive = try ZipArchive(data)
            guard let entry = try archive.read(documentPath) else { throw ForeignImportError.wrongFormat }
            xml = entry
        } catch let error as ZipArchive.Error {
            throw error == .tooLarge ? .tooLarge : (error == .notAnArchive ? .wrongFormat : .damaged)
        } catch {
            throw .wrongFormat
        }
        let documents = try parse(xml)
        var maps: [GraphState] = []
        var report = ImportReport()
        for document in documents {
            maps.append(try FreeMindMap.graph(from: document, title: fileName, now: now))
            report.merge(document.report)
        }
        return ForeignImport(maps: maps, report: report)
    }

    /// One document per `mindmap` element, each as FreeMind's styled draft
    /// so colours, folding and connections are built the same way.
    public static func parse(_ xml: Data) throws(ForeignImportError) -> [FreeMindMap.Document] {
        let reader = SimpleMindReader()
        let parser = XMLParser(data: xml)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        let parsed = parser.parse()
        if reader.isWrongFormat { throw .wrongFormat }
        guard parsed, reader.sawRoot else { throw .damaged }
        let documents = reader.maps.compactMap { $0.document() }
        if documents.isEmpty { throw .emptyDocument }
        return documents
    }

    /// SimpleMind writes `\N` for a line break inside an attribute.
    static func text(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\N", with: "\n")
    }
}

private final class SimpleMindReader: NSObject, XMLParserDelegate {
    struct Topic {
        var id: String
        var parent: String
        var title: String
        var note = ""
        var link: TopicLink?
        var linkNote: String?
        var taskState: TaskState?
        var isFolded = false
        var color: TopicColor?
    }

    struct Relation {
        var source: String
        var target: String
        var label: String?
    }

    struct Map {
        var centralID: String?
        var topics: [Topic] = []
        var relations: [Relation] = []
        var report = ImportReport()

        /// The flat list as a tree in file order: central theme first, then
        /// other parentless topics (floating) under it. Iterative, so a deep
        /// chain of parents cannot overflow the stack; a cycle is cut where
        /// it closes, and its topics join the central topic.
        func document() -> FreeMindMap.Document? {
            guard !topics.isEmpty else { return nil }
            var indexByID: [String: Int] = [:]
            for (index, topic) in topics.enumerated() where indexByID[topic.id] == nil {
                indexByID[topic.id] = index
            }
            var children: [Int: [Int]] = [:]
            var roots: [Int] = []
            for (index, topic) in topics.enumerated() {
                if let parent = indexByID[topic.parent], parent != index, indexByID[topic.id] == index {
                    children[parent, default: []].append(index)
                } else {
                    roots.append(index)
                }
            }
            let central = centralID.flatMap { indexByID[$0] }.flatMap { roots.contains($0) ? $0 : nil } ?? roots.first
            var order: [(index: Int, depth: Int)] = []
            var visited = Set<Int>()
            func walk(from start: Int, depth: Int) {
                var stack = [(start, depth)]
                while let (index, depth) = stack.popLast() {
                    guard visited.insert(index).inserted else { continue }
                    order.append((index, depth))
                    for child in (children[index] ?? []).reversed() { stack.append((child, depth + 1)) }
                }
            }
            if let central {
                walk(from: central, depth: 0)
                for root in roots where root != central { walk(from: root, depth: 1) }
            }
            // Topics only reachable through a cycle: keep them under the central topic.
            for index in topics.indices where !visited.contains(index) { walk(from: index, depth: 1) }

            var items: [OutlineDraft.Item] = []
            var styles: [FreeMindMap.Style] = []
            var linksBySource: [String: [FreeMindMap.ArrowLink]] = [:]
            for relation in relations {
                linksBySource[relation.source, default: []].append(
                    FreeMindMap.ArrowLink(destination: relation.target, label: relation.label, arrowHeads: .end)
                )
            }
            for (index, depth) in order {
                let topic = topics[index]
                let notes = [topic.note.isEmpty ? nil : topic.note, topic.linkNote].compactMap(\.self)
                items.append(OutlineDraft.Item(
                    depth: depth,
                    title: topic.title,
                    note: notes.isEmpty ? nil : notes.joined(separator: "\n\n"),
                    link: topic.link,
                    taskState: topic.taskState
                ))
                styles.append(FreeMindMap.Style(
                    fileID: topic.id,
                    color: topic.color,
                    isFolded: topic.isFolded,
                    arrowLinks: indexByID[topic.id] == index ? linksBySource[topic.id] ?? [] : []
                ))
            }
            return FreeMindMap.Document(draft: OutlineDraft(items: items), styles: styles, report: report)
        }
    }

    private(set) var maps: [Map] = []
    private(set) var sawRoot = false
    private(set) var isWrongFormat = false

    private var path: [String] = []
    private var topic: Topic?
    private var relation: Relation?
    private var text = ""
    private var isReadingText = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        defer { path.append(name) }
        if path.isEmpty {
            guard name == "simplemind-mindmaps" else {
                isWrongFormat = true
                parser.abortParsing()
                return
            }
            sawRoot = true
            return
        }
        let parent = path.last
        switch (parent, name) {
        case ("simplemind-mindmaps", "mindmap"):
            maps.append(Map())
        case ("meta", "main-centraltheme"):
            if !maps.isEmpty { maps[maps.count - 1].centralID = attributes["id"] }
        case ("topics", "topic"):
            topic = Topic(
                id: attributes["id"] ?? UUID().uuidString,
                parent: attributes["parent"] ?? "-1",
                title: SimpleMindMap.text(attributes["text"] ?? ""),
                taskState: attributes["checkbox"] == "True" ? (attributes["checked"] == "True" ? .done : .open) : nil,
                isFolded: attributes["collapsed"] == "True"
            )
        case ("topic", "note") where topic != nil,
             ("text", "note") where relation != nil:
            text = ""
            isReadingText = true
        case ("topic", "link") where topic != nil:
            guard let url = attributes["urllink"], !url.isEmpty else { break }
            if let link = TopicLink.normalized(url) {
                topic?.link = link
            } else if !url.hasPrefix("topic:") {
                // `cloud://` and file paths do not open here; keep them readable.
                topic?.linkNote = url
            }
        case ("topic", "strokecolor") where topic != nil:
            topic?.color = Self.color(attributes)
        case ("topic", "image"), ("images", "image"):
            if !maps.isEmpty { maps[maps.count - 1].report.record(.image) }
        case ("relations", "relation"):
            relation = Relation(source: attributes["source"] ?? "", target: attributes["target"] ?? "")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingText { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        path.removeLast()
        switch name {
        case "note" where isReadingText:
            isReadingText = false
            let note = Self.trimmedLines(text)
            if relation != nil {
                if relation?.label == nil, !note.isEmpty { relation?.label = note }
            } else if !note.isEmpty {
                topic?.note = note
            }
        case "topic" where path.last == "topics":
            if let topic, !maps.isEmpty { maps[maps.count - 1].topics.append(topic) }
            topic = nil
        case "relation":
            if let relation, !maps.isEmpty { maps[maps.count - 1].relations.append(relation) }
            relation = nil
        default:
            break
        }
    }

    /// Notes are written indented inside the element; the indent is not text.
    static func trimmedLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func color(_ attributes: [String: String]) -> TopicColor? {
        guard let red = attributes["r"].flatMap(Int.init), let green = attributes["g"].flatMap(Int.init),
              let blue = attributes["b"].flatMap(Int.init)
        else { return nil }
        return FreeMindMap.paletteColor(String(format: "#%02X%02X%02X", red & 0xFF, green & 0xFF, blue & 0xFF))
    }
}
