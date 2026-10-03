import Foundation
import MindMapDomain
import MindMapGraph

/// FreeMind and Freeplane maps (`.mm`, FR-IO-10).
///
/// Format sources: FreeMind 1.0's schema `freemind.xsd` (shipped with the
/// FreeMind sources, freemind.sourceforge.net) and the Freeplane 1.x file
/// format page of the Freeplane wiki and docs (docs.freeplane.org). Both
/// write `<map version="…">` holding one root `node`; nodes nest.
///
/// Reading, per `node`:
/// - title: `TEXT`, else Freeplane's `LOCALIZED_TEXT`, else the text of a
///   `richcontent TYPE="NODE"` (HTML, read as plain lines);
/// - note: `richcontent TYPE="DETAILS"` (Freeplane) then `TYPE="NOTE"`;
/// - `LINK`: a web or mail link becomes the topic's link; `#ID_…` (a link to
///   another node) becomes a Connection; anything else stays in the note;
/// - `arrowlink DESTINATION="…"` becomes a Connection, with its label, arrow
///   heads and colour when the palette has one;
/// - colour: the branch's `edge COLOR`, else `BACKGROUND_COLOR`, else
///   `COLOR`, mapped to the nearest palette token by hue; greys and black
///   map to none, so black text does not paint every topic;
/// - `FOLDED="true"` collapses the topic.
///
/// Icons and pictures have nowhere to go and are counted in the report.
/// Everything else (fonts, clouds, attributes, styles) is skipped.
public enum FreeMindMap {
    /// One `arrowlink`, or a `#ID` `LINK`, by the other node's file ID.
    public struct ArrowLink: Hashable, Sendable {
        public var destination: String
        public var label: String?
        public var arrowHeads: EdgeArrowHeads?
        public var color: TopicColor?
    }

    /// What a node had besides its title, note and link: one per draft item.
    public struct Style: Hashable, Sendable {
        /// The node's `ID` in the file, for links pointing at it.
        public var fileID: String?
        public var color: TopicColor?
        public var isFolded = false
        public var arrowLinks: [ArrowLink] = []
    }

    public struct Document: Hashable, Sendable {
        public var draft: OutlineDraft
        /// Parallel to `draft.items`.
        public var styles: [Style]
        public var report: ImportReport
    }

    public static func parse(_ data: Data) throws(ForeignImportError) -> Document {
        let reader = FreeMindReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        // A map has no business loading anything from outside itself.
        parser.shouldResolveExternalEntities = false
        let parsed = parser.parse()
        if reader.isWrongFormat { throw .wrongFormat }
        guard parsed, reader.sawRoot else { throw .damaged }
        let document = reader.document
        if document.draft.isEmpty { throw .emptyDocument }
        return document
    }

    /// The map the document describes. `title` names the central topic when
    /// the file has several top-level nodes, which FreeMind never writes.
    public static func graph(from document: Document, title: String, now: Date = .now) throws(ForeignImportError) -> GraphState {
        guard let plain = try? GraphState.imported(from: document.draft, title: title, now: now) else {
            throw .emptyDocument
        }
        // `imported` adds the draft in reading order, so a walk of the tree
        // lines its topics up with the draft items (after a central topic it
        // made itself, for several top-level nodes).
        guard let rootID = plain.map.rootNodeID,
              let walk = try? OutlineWalk.nodes(of: plain, from: rootID)
        else { return plain }
        let offset = document.draft.topLevelCount == 1 ? 0 : 1
        let nodeIDs = walk.dropFirst(offset).map(\.0.id)
        guard nodeIDs.count == document.styles.count else { return plain }

        let commands = styleCommands(document, nodeIDs: nodeIDs, parentIndices: parentIndices(of: document.draft), rootID: rootID)
        guard !commands.isEmpty, var engine = try? GraphEngine(state: plain, clock: { now }) else { return plain }
        // Styling is a bonus on top of the topics: if it fails, keep them all unstyled.
        guard (try? engine.execute(BatchCommand(commands))) != nil else { return plain }
        return engine.state
    }

    private static func parentIndices(of draft: OutlineDraft) -> [Int?] {
        var path: [Int] = []
        return draft.items.enumerated().map { index, item in
            path.removeLast(path.count - item.depth)
            let parent = path.last
            path.append(index)
            return parent
        }
    }

    private static func styleCommands(_ document: Document, nodeIDs: [NodeID], parentIndices: [Int?], rootID: NodeID) -> [any GraphCommand] {
        var commands: [any GraphCommand] = []
        var resolved: [TopicColor?] = []
        var hasChildren = Array(repeating: false, count: nodeIDs.count)
        for parent in parentIndices.compactMap(\.self) { hasChildren[parent] = true }

        for (index, style) in document.styles.enumerated() {
            let id = nodeIDs[index]
            // A colour applies to the branch, so set it only where it changes.
            let inherited = parentIndices[index].flatMap { resolved[$0] }
            let color = style.color ?? inherited
            resolved.append(color)
            if color != inherited {
                commands.append(SetNodeStyleCommand(nodeIDs: [id], color: .set(color)))
            }
            if style.isFolded, hasChildren[index], id != rootID {
                commands.append(UpdateNodeCommand(nodeID: id, .isCollapsed(true)))
            }
        }

        var byFileID: [String: NodeID] = [:]
        for (index, style) in document.styles.enumerated() {
            guard let fileID = style.fileID, byFileID[fileID] == nil else { continue }
            byFileID[fileID] = nodeIDs[index]
        }
        // Checked here so one bad link cannot fail the batch and lose the rest.
        var linked: Set<[NodeID]> = []
        for (index, style) in document.styles.enumerated() {
            let source = nodeIDs[index]
            for link in style.arrowLinks {
                guard let target = byFileID[link.destination], target != source,
                      linked.insert([source, target]).inserted
                else { continue }
                let edgeID = EdgeID()
                commands.append(ConnectNodesCommand(edgeID: edgeID, from: source, to: target, label: link.label))
                commands.append(UpdateEdgeCommand(
                    edgeID: edgeID,
                    arrowHeads: link.arrowHeads.map { .set($0) } ?? .keep,
                    color: link.color.map { .set($0) } ?? .keep
                ))
            }
        }
        return commands
    }

    // MARK: Colours

    /// The palette token nearest a `#rrggbb` colour by hue; nil for greys,
    /// near-black and anything that does not parse.
    public static func paletteColor(_ hex: String?) -> TopicColor? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), text.hasPrefix("#") else { return nil }
        text.removeFirst()
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let chroma = maximum - minimum
        // Thresholds are a judgement call: below them a colour reads as grey or black.
        guard maximum >= 0.25, chroma / maximum >= 0.2 else { return nil }

        var hue: Double
        if maximum == red {
            hue = 60 * ((green - blue) / chroma)
        } else if maximum == green {
            hue = 60 * ((blue - red) / chroma + 2)
        } else {
            hue = 60 * ((red - green) / chroma + 4)
        }
        if hue < 0 { hue += 360 }

        switch hue {
        case ..<15: return .rose
        case ..<70: return .amber
        case ..<165: return .green
        case ..<200: return .teal
        case ..<255: return .blue
        case ..<330: return .violet
        default: return .rose
        }
    }

    /// FreeMind's arrow names: `None` is no head, anything else (`Default`) one.
    static func arrowHeads(start: String?, end: String?) -> EdgeArrowHeads {
        // Absent attributes take FreeMind's defaults: no start arrow, an end arrow.
        let hasStart = (start ?? "None").caseInsensitiveCompare("None") != .orderedSame
        let hasEnd = (end ?? "Default").caseInsensitiveCompare("None") != .orderedSame
        switch (hasStart, hasEnd) {
        case (true, true): return .both
        case (true, false): return .start
        case (false, true): return .end
        case (false, false): return .none
        }
    }
}

/// Collects nodes as `XMLParser` reports them. The parser streams, so a
/// deeply nested map costs a stack of indices, not call stack.
private final class FreeMindReader: NSObject, XMLParserDelegate {
    private struct Node {
        var title: String
        var depth: Int
        var details: String?
        var note: String?
        var linkNote: String?
        var link: TopicLink?
        var style: FreeMindMap.Style
        var textColor: TopicColor?
        var backgroundColor: TopicColor?
        var edgeColor: TopicColor?
    }

    /// Text of a `richcontent` being read, as lines of HTML or plain text.
    private struct RichText {
        var type: String
        var isPlain: Bool
        var lines: [String] = [""]
        /// Inside `head`, `style` or `script`, whose text is not content.
        var hiddenDepth = 0
        var depth = 0
    }

    private(set) var sawRoot = false
    private(set) var isWrongFormat = false

    private var nodes: [Node] = []
    /// Indices into `nodes` from the root to the node being read.
    private var open: [Int] = []
    private var path: [String] = []
    private var report = ImportReport()
    private var rich: RichText?
    /// Depth inside an element that is not part of the tree (Freeplane's
    /// `hook` with its map styles, say); everything there is skipped.
    private var skippedDepth: Int?

    var document: FreeMindMap.Document {
        let items = nodes.map { node in
            let note = [node.details, node.note, node.linkNote].compactMap(\.self).joined(separator: "\n\n")
            return OutlineDraft.Item(depth: node.depth, title: node.title, note: note.isEmpty ? nil : note, link: node.link)
        }
        let styles = nodes.map { node in
            var style = node.style
            style.color = node.edgeColor ?? node.backgroundColor ?? node.textColor
            return style
        }
        return FreeMindMap.Document(draft: OutlineDraft(items: items), styles: styles, report: report)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        defer { path.append(elementName) }
        guard sawRoot else {
            sawRoot = true
            if elementName != "map" {
                isWrongFormat = true
                parser.abortParsing()
            }
            return
        }
        if rich != nil {
            richStart(elementName)
            return
        }
        if let depth = skippedDepth {
            skippedDepth = depth + 1
            return
        }
        let parent = path.last
        switch elementName {
        case "node" where parent == "node" || path == ["map"]:
            startNode(attributes)
        case "richcontent" where parent == "node":
            let type = attributes["TYPE"]?.uppercased() ?? "NODE"
            let isPlain = attributes["CONTENT-TYPE"]?.lowercased().hasPrefix("plain") ?? false
            rich = RichText(type: type, isPlain: isPlain)
        case "arrowlink" where parent == "node":
            guard let index = open.last, let destination = attributes["DESTINATION"] else { break }
            let label = [attributes["MIDDLE_LABEL"], attributes["SOURCE_LABEL"], attributes["TARGET_LABEL"]]
                .compactMap(\.self)
                .first { !$0.allSatisfy(\.isWhitespace) }
            nodes[index].style.arrowLinks.append(FreeMindMap.ArrowLink(
                destination: destination,
                label: label,
                arrowHeads: FreeMindMap.arrowHeads(start: attributes["STARTARROW"], end: attributes["ENDARROW"]),
                color: FreeMindMap.paletteColor(attributes["COLOR"])
            ))
        case "edge" where parent == "node":
            if let index = open.last { nodes[index].edgeColor = FreeMindMap.paletteColor(attributes["COLOR"]) }
        case "icon" where parent == "node":
            report.record(.icon)
        case "hook" where parent == "node":
            // Freeplane keeps a picture on a node as an external object hook.
            if attributes["NAME"] == "ExternalObject" { report.record(.image) }
            skippedDepth = 0
        default:
            // Fonts, clouds, attributes, map styles: nothing in a map to put them in.
            skippedDepth = 0
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        path.removeLast()
        if rich != nil {
            if rich!.depth > 0 {
                richEnd(elementName)
            } else {
                finishRich()
            }
            return
        }
        if let depth = skippedDepth {
            skippedDepth = depth == 0 ? nil : depth - 1
            return
        }
        if elementName == "node", !open.isEmpty {
            open.removeLast()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard var text = rich, text.hiddenDepth == 0 else { return }
        if text.isPlain {
            let parts = string.split(separator: "\n", omittingEmptySubsequences: false)
            text.lines[text.lines.count - 1] += parts[0]
            text.lines += parts.dropFirst().map(String.init)
        } else {
            // HTML: any run of whitespace is one space.
            let collapsed = string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            var line = text.lines[text.lines.count - 1]
            if string.first?.isWhitespace == true, !line.isEmpty, line.last != " " { line += " " }
            line += collapsed
            if string.last?.isWhitespace == true, !collapsed.isEmpty { line += " " }
            text.lines[text.lines.count - 1] = line
        }
        rich = text
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            self.parser(parser, foundCharacters: string)
        }
    }

    // MARK: Nodes

    private func startNode(_ attributes: [String: String]) {
        var node = Node(
            title: attributes["TEXT"] ?? attributes["LOCALIZED_TEXT"] ?? "",
            depth: open.count,
            style: FreeMindMap.Style(fileID: attributes["ID"], isFolded: attributes["FOLDED"]?.lowercased() == "true")
        )
        node.textColor = FreeMindMap.paletteColor(attributes["COLOR"])
        node.backgroundColor = FreeMindMap.paletteColor(attributes["BACKGROUND_COLOR"])
        if let url = attributes["LINK"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            if url.hasPrefix("#"), url.count > 1 {
                // A link to another node of the map, by its ID.
                node.style.arrowLinks.append(FreeMindMap.ArrowLink(destination: String(url.dropFirst()), arrowHeads: .end))
            } else if let link = TopicLink.normalized(url) {
                node.link = link
            } else {
                // A file path or a scheme this build does not open stays readable.
                node.linkNote = url
            }
        }
        nodes.append(node)
        open.append(nodes.count - 1)
    }

    // MARK: Rich content

    private static let blocks: Set<String> = [
        "p", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "blockquote", "ul", "ol", "table",
    ]
    private static let hidden: Set<String> = ["head", "style", "script"]

    private func richStart(_ element: String) {
        let name = element.lowercased()
        rich!.depth += 1
        if Self.hidden.contains(name) || rich!.hiddenDepth > 0 { rich!.hiddenDepth += 1 }
        if name == "img" { report.record(.image) }
        if name == "br" {
            breakLine(always: true)
        } else if Self.blocks.contains(name) {
            breakLine(always: false)
        }
    }

    private func richEnd(_ element: String) {
        let name = element.lowercased()
        rich!.depth -= 1
        if rich!.hiddenDepth > 0 { rich!.hiddenDepth -= 1 }
        if Self.blocks.contains(name) { breakLine(always: false) }
    }

    /// A block starts a line only when the current one has text, so `</p><p>`
    /// is one line break, not a blank line; `br` always breaks.
    private func breakLine(always: Bool) {
        guard let text = rich, !text.isPlain else { return }
        guard always || !(text.lines.last ?? "").allSatisfy(\.isWhitespace) else { return }
        rich!.lines.append("")
    }

    private func finishRich() {
        guard let text = rich else { return }
        rich = nil
        guard let index = open.last else { return }
        let body = Self.joined(text.lines, trimming: !text.isPlain)
        switch text.type {
        case "NOTE": nodes[index].note = body
        case "DETAILS": nodes[index].details = body
        default:
            // The title is rich text only when the node has no `TEXT`.
            if nodes[index].title.isEmpty, let body { nodes[index].title = body }
        }
    }

    /// Lines with blank runs squeezed to one and blank ends dropped; nil when blank.
    private static func joined(_ lines: [String], trimming: Bool) -> String? {
        var result: [String] = []
        for line in lines {
            let line = trimming ? line.replacing("\u{00A0}", with: " ").trimmingCharacters(in: .whitespaces) : line
            if line.allSatisfy(\.isWhitespace) {
                if let last = result.last, !last.isEmpty { result.append("") }
            } else {
                result.append(line)
            }
        }
        while let last = result.last, last.allSatisfy(\.isWhitespace) { result.removeLast() }
        return result.isEmpty ? nil : result.joined(separator: "\n")
    }
}
