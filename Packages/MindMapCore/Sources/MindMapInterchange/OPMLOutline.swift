import Foundation
import MindMapDomain
import MindMapGraph

/// OPML 2.0 (opml.org/spec2.opml), the outline format outliners and mind map
/// apps share (FR-IO-06).
///
/// Reading: each `outline` in `body` is a topic, nested as in the file; its
/// `text` is the title and `_note` the note. `type="link"` (and the `url` of
/// `type="include"`, the `htmlUrl` or `xmlUrl` of `type="rss"`) becomes the
/// topic's link. Any other attribute or element is skipped, so files from
/// apps that add their own (`_status`, `created`, `isComment`) still read.
/// OPML 1.0 files read the same way.
///
/// Writing: the map's title in `head`, then the central topic as the one
/// top-level outline with every topic under it, floating topics after it.
public enum OPMLOutline {
    /// A parsed OPML file: the outline, `head`'s title and what could not be kept.
    public struct Document: Hashable, Sendable {
        public var title: String?
        public var draft: OutlineDraft
        public var report: ImportReport
    }

    public static func parse(_ data: Data) throws(ForeignImportError) -> Document {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        // An OPML file has no business loading anything from outside itself.
        parser.shouldResolveExternalEntities = false
        let parsed = parser.parse()
        if reader.isWrongFormat { throw .wrongFormat }
        guard parsed, reader.sawRoot else { throw .damaged }
        let document = reader.document
        if document.draft.isEmpty { throw .emptyDocument }
        return document
    }

    /// The map, or the branch under `branchID`, as an OPML 2.0 document in UTF-8.
    public static func export(
        _ state: GraphState,
        branch branchID: NodeID? = nil,
        includeNotes: Bool = true
    ) throws -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<opml version="2.0">"#,
            "  <head>",
            "    <title>\(escapedText(state.map.title))</title>",
            "  </head>",
            "  <body>",
        ]
        let nodes = try OutlineWalk.nodes(of: state, from: branchID)
        for (index, (node, depth)) in nodes.enumerated() {
            let indent = String(repeating: "  ", count: depth + 2)
            var attributes = [("text", TextLines.exportTitle(of: node))]
            if includeNotes, let note = node.note, !note.allSatisfy(\.isWhitespace) {
                attributes.append(("_note", note))
            }
            // Only a link this build opens, so it reads back as one.
            if let link = node.link, link.url != nil {
                attributes += [("type", "link"), ("url", link.string)]
            }
            let opening = indent + "<outline" + attributes.map { " \($0)=\"\(escapedAttribute($1))\"" }.joined()
            let nextDepth = index + 1 < nodes.count ? nodes[index + 1].1 : 0
            if nextDepth > depth {
                lines.append(opening + ">")
                continue
            }
            lines.append(opening + "/>")
            // Close every outline the next one is not inside.
            for closed in stride(from: depth - 1, through: nextDepth, by: -1) {
                lines.append(String(repeating: "  ", count: closed + 2) + "</outline>")
            }
        }
        lines += ["  </body>", "</opml>"]
        return lines.joined(separator: "\n") + "\n"
    }

    @concurrent
    public static func exportData(
        _ state: GraphState,
        branch branchID: NodeID? = nil,
        includeNotes: Bool = true
    ) async throws -> Data {
        Data(try export(state, branch: branchID, includeNotes: includeNotes).utf8)
    }

    // MARK: Escaping

    static func escapedText(_ text: String) -> String {
        var result = ""
        for scalar in xmlScalars(text) {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Line breaks and tabs are written as character references: a parser
    /// turns literal ones in an attribute into spaces, and a note would lose its lines.
    static func escapedAttribute(_ text: String) -> String {
        var result = ""
        for scalar in xmlScalars(text) {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "\n": result += "&#10;"
            case "\r": result += "&#13;"
            case "\t": result += "&#9;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// The scalars XML 1.0 can hold. Other control characters cannot be
    /// written even as references, so they are left out rather than making a
    /// file no app opens.
    private static func xmlScalars(_ text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x9, 0xA, 0xD: true
            case 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: true
            default: false
            }
        }
    }
}

/// Collects outlines as `XMLParser` reports them. The parser streams, so a
/// deeply nested file costs a counter, not stack.
private final class Reader: NSObject, XMLParserDelegate {
    private(set) var sawRoot = false
    private(set) var isWrongFormat = false

    private var builder = DraftBuilder()
    private var report = ImportReport()
    private var title: String?
    /// The element names from the root down to the current one.
    private var path: [String] = []
    /// Outline depth below `body`; elements other than `outline` do not count.
    private var outlineDepth = 0
    /// Depth of an `outline` nested in an element that is not an outline,
    /// which is not part of the tree; everything inside it is skipped.
    private var skippedDepth: Int?
    private var titleText: String?

    var document: OPMLOutline.Document {
        OPMLOutline.Document(title: title, draft: builder.finish(), report: report)
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
            if elementName != "opml" {
                isWrongFormat = true
                parser.abortParsing()
            }
            return
        }
        if path == ["opml", "head"], elementName == "title" {
            titleText = ""
            return
        }
        guard elementName == "outline", skippedDepth == nil else {
            if skippedDepth != nil { skippedDepth! += 1 }
            return
        }
        // An outline counts only directly in `body` or in another outline.
        let parent = path.last
        guard parent == "outline" || path == ["opml", "body"] else {
            skippedDepth = 0
            return
        }
        read(attributes)
        outlineDepth += 1
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        path.removeLast()
        if let depth = skippedDepth {
            skippedDepth = depth == 0 ? nil : depth - 1
            return
        }
        if elementName == "outline", path.last == "outline" || path == ["opml", "body"] {
            outlineDepth -= 1
        } else if elementName == "title", let text = titleText {
            title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            titleText = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        titleText? += string
    }

    private func read(_ attributes: [String: String]) {
        let url = linkURL(attributes)
        let link = url.flatMap(TopicLink.normalized)
        let index = builder.add(depth: outlineDepth, title: attributes["text"] ?? "", link: link)
        if let note = attributes["_note"] {
            builder.appendNote(note, to: .item(index), afterBlank: true)
        }
        // A link this build does not open (a `file:` URL, say) stays readable in the note.
        if let url, link == nil, !url.allSatisfy(\.isWhitespace) {
            builder.appendNote(url, to: .item(index), afterBlank: true)
        }
    }

    private func linkURL(_ attributes: [String: String]) -> String? {
        switch attributes["type"]?.lowercased() {
        case "link":
            return attributes["url"]
        case "include":
            // The outline behind it would have to be downloaded; the topic keeps the URL.
            report.record(.includedOutline)
            return attributes["url"]
        case "rss":
            return attributes["htmlUrl"] ?? attributes["xmlUrl"]
        default:
            return nil
        }
    }
}
