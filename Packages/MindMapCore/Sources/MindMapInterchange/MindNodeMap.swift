import Foundation
import MindMapDomain
import MindMapGraph

/// MindNode documents (`.mindnode`, FR-IO-12, spike MM-104).
///
/// IdeasOnCanvas publishes no specification. The layout was read from six
/// documents MindNode saved (`version` 6 and 7), public on GitHub:
/// `spatial-computing/mintcast`, `servicemesher/istio-knowledge-map`,
/// `servicemesher/istio-handbook`, `wardseptember/notes`, `MuYunyun/blog`,
/// `ducafecat/flutter_ducafecat_news_getx` (each `*.mindnode/contents.xml`).
///
/// A `.mindnode` document is a package (a folder): `contents.xml` is a
/// property list, binary in every sample despite its name, beside
/// `viewState.plist`, `style.mindnodestyle/` and `QuickLook/`. Only
/// `contents.xml` is read, so this takes its bytes; the caller opens the folder.
///
/// `canvas.mindMaps[].mainNode` is a tree of nodes (`subnodes`); each map on
/// the canvas is a top-level tree, so several go under a central topic named
/// by the file. Per node: `title.text` and `note.text` are HTML fragments read
/// as plain lines, `hasFoldedSubnodes` folds it, `pathStyle.strokeStyle.color`
/// (`{r, g, b, a}`, 0…1) colours the branch by hue, `task` makes it a task.
/// `canvas.crossConnections[]` (`endPoints.startNodeID`/`endNodeID`,
/// `title.text`, `arrowStyle.startArrow`/`endArrow`) become Connections.
/// `task.state` is read as open: one sample has a task and its meaning is not
/// confirmed. Boundaries (`canvas.boundaries`) are counted.
public enum MindNodeMap {
    @concurrent
    public static func read(contents: Data, fileName: String, now: Date = .now) async throws(ForeignImportError) -> ForeignImport {
        let document = try parse(contents)
        let map = try FreeMindMap.graph(from: document, title: fileName, now: now)
        return ForeignImport(maps: [map], report: document.report)
    }

    public static func parse(_ contents: Data) throws(ForeignImportError) -> FreeMindMap.Document {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: contents, format: nil)
        } catch {
            throw .wrongFormat
        }
        guard let root = plist as? [String: Any], let canvas = root["canvas"] as? [String: Any],
              let mindMaps = canvas["mindMaps"] as? [[String: Any]]
        else { throw .wrongFormat }

        var linksBySource: [String: [FreeMindMap.ArrowLink]] = [:]
        for connection in canvas["crossConnections"] as? [[String: Any]] ?? [] {
            let ends = connection["endPoints"] as? [String: Any]
            guard let source = ends?["startNodeID"] as? String, let target = ends?["endNodeID"] as? String else { continue }
            let arrows = connection["arrowStyle"] as? [String: Any]
            let start = (arrows?["startArrow"] as? Int ?? 0) != 0
            let end = (arrows?["endArrow"] as? Int ?? 1) != 0
            let label = plainText((connection["title"] as? [String: Any])?["text"] as? String ?? "")
            linksBySource[source, default: []].append(FreeMindMap.ArrowLink(
                destination: target,
                label: label.isEmpty ? nil : label,
                arrowHeads: start ? (end ? .both : .start) : (end ? .end : EdgeArrowHeads.none)
            ))
        }

        var items: [OutlineDraft.Item] = []
        var styles: [FreeMindMap.Style] = []
        var report = ImportReport()
        report.record(.boundary, count: (canvas["boundaries"] as? [Any])?.count ?? 0)
        // Iterative pre-order walk: a deep map cannot overflow the stack.
        var stack: [(node: [String: Any], depth: Int)] = mindMaps.reversed().compactMap { map in
            (map["mainNode"] as? [String: Any]).map { ($0, 0) }
        }
        while let (node, depth) = stack.popLast() {
            let id = node["nodeID"] as? String
            let note = plainText((node["note"] as? [String: Any])?["text"] as? String ?? "")
            items.append(OutlineDraft.Item(
                depth: depth,
                title: plainText((node["title"] as? [String: Any])?["text"] as? String ?? ""),
                note: note.isEmpty ? nil : note,
                taskState: node["task"] is [String: Any] ? .open : nil
            ))
            let stroke = ((node["pathStyle"] as? [String: Any])?["strokeStyle"] as? [String: Any])?["color"] as? String
            styles.append(FreeMindMap.Style(
                fileID: id,
                color: stroke.flatMap(color),
                isFolded: node["hasFoldedSubnodes"] as? Bool ?? false,
                arrowLinks: id.flatMap { linksBySource[$0] } ?? []
            ))
            for child in (node["subnodes"] as? [[String: Any]] ?? []).reversed() {
                stack.append((child, depth + 1))
            }
        }
        if items.isEmpty { throw .emptyDocument }
        return FreeMindMap.Document(draft: OutlineDraft(items: items), styles: styles, report: report)
    }

    /// `{0.464310, 0.078533, 0.566906, 1.000000}` to the nearest palette token.
    static func color(_ text: String) -> TopicColor? {
        let parts = text.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        let bytes = parts.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return FreeMindMap.paletteColor(String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2]))
    }

    /// MindNode's HTML fragments (`<p style='…'>Title</p>`, spans, `<br>`) as
    /// plain lines. Not an HTML parser: tags are dropped, block ends break
    /// lines, the common entities are decoded, whitespace collapses.
    static func plainText(_ html: String) -> String {
        guard html.contains("<") || html.contains("&") else {
            return html.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lines: [String] = []
        var line = ""
        var index = html.startIndex
        func breakLine() {
            lines.append(line.trimmingCharacters(in: .whitespaces))
            line = ""
        }
        while index < html.endIndex {
            let character = html[index]
            if character == "<", let close = html[index...].firstIndex(of: ">") {
                let tag = html[html.index(after: index)..<close].lowercased()
                let name = tag.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }
                if name == "br" || (tag.hasPrefix("/") && ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6"].contains(String(name))) {
                    breakLine()
                }
                index = html.index(after: close)
            } else if character == "&", let semicolon = html[index...].prefix(10).firstIndex(of: ";") {
                let entity = String(html[html.index(after: index)..<semicolon])
                if let decoded = decode(entity) {
                    line.append(decoded)
                    index = html.index(after: semicolon)
                } else {
                    line.append(character)
                    index = html.index(after: index)
                }
            } else {
                if character.isWhitespace {
                    if !line.isEmpty, line.last != " " { line.append(" ") }
                } else {
                    line.append(character)
                }
                index = html.index(after: index)
            }
        }
        breakLine()
        while lines.last?.isEmpty == true { lines.removeLast() }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        return lines.joined(separator: "\n")
    }

    private static func decode(_ entity: String) -> String? {
        switch entity {
        case "lt": return "<"
        case "gt": return ">"
        case "amp": return "&"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{00A0}"
        default:
            guard entity.hasPrefix("#") else { return nil }
            let digits = entity.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
    }
}
