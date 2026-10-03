import Foundation
import MindMapDomain
import MindMapGraph

/// iThoughts maps (`.itmz`, FR-IO-12, spike MM-104).
///
/// toketaWare stopped trading on 2024-01-30 and never published the format.
/// The layout was read from a file iThoughts 7.4 for iPad saved
/// (`michalradacz/Czech_EG_objects_and_tools`, `mapdata.xml`, public on
/// GitHub) and the attribute list in Brett Terpstra's iThoughts converter
/// (gist `ttscoff/58a3f7d69fff63caa11766f23647f888`).
///
/// An `.itmz` file is a ZIP holding `mapdata.xml`:
/// `<iThoughts version="4.0" app="com.toketaware.ios.ithoughts"><topics>
/// <topic uuid text note link color position …>` with children nested.
/// The first top-level topic is the central topic; further top-level topics
/// (floating in iThoughts) go under it.
///
/// Reading, per topic: `text` as the title, `note` as the note, `link` with a
/// web or mail URL as the link (anything else into the note), `color`
/// (`RRGGBB`) by hue. Relationships and summaries (`summary1`/`summary2`) are
/// counted, not built: no file at hand shows their attributes.
public enum IThoughtsMap {
    static let documentPath = "mapdata.xml"

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
        let document = try parse(xml)
        let map = try FreeMindMap.graph(from: document, title: fileName, now: now)
        return ForeignImport(maps: [map], report: document.report)
    }

    public static func parse(_ xml: Data) throws(ForeignImportError) -> FreeMindMap.Document {
        let reader = IThoughtsReader()
        let parser = XMLParser(data: xml)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        let parsed = parser.parse()
        if reader.isWrongFormat { throw .wrongFormat }
        guard parsed, reader.sawRoot else { throw .damaged }
        if reader.items.isEmpty { throw .emptyDocument }
        return FreeMindMap.Document(draft: OutlineDraft(items: reader.items), styles: reader.styles, report: reader.report)
    }
}

private final class IThoughtsReader: NSObject, XMLParserDelegate {
    private(set) var items: [OutlineDraft.Item] = []
    private(set) var styles: [FreeMindMap.Style] = []
    private(set) var report = ImportReport()
    private(set) var sawRoot = false
    private(set) var isWrongFormat = false

    private var path: [String] = []
    /// Depth of the open `topic` elements; 0 outside any.
    private var depth = 0
    private var topLevelCount = 0

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        defer { path.append(name) }
        if path.isEmpty {
            // Some exports start at `topics` (Terpstra's converter notes).
            guard name == "iThoughts" || name == "topics" else {
                isWrongFormat = true
                parser.abortParsing()
                return
            }
            sawRoot = true
            return
        }
        switch (path.last, name) {
        case ("topics", "topic"), ("topic", "topic"):
            if depth == 0 { topLevelCount += 1 }
            // A second top-level topic floats in iThoughts: keep it under the central one.
            let itemDepth = depth + (topLevelCount > 1 ? 1 : 0)
            depth += 1
            topic(attributes, depth: itemDepth)
        case ("relationships", _):
            report.record(.connection)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        path.removeLast()
        if name == "topic", depth > 0 { depth -= 1 }
    }

    private func topic(_ attributes: [String: String], depth: Int) {
        var notes: [String] = []
        if let note = attributes["note"]?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            notes.append(note)
        }
        var link: TopicLink?
        if let url = attributes["link"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            if let normalized = TopicLink.normalized(url) {
                link = normalized
            } else {
                notes.append(url)
            }
        }
        if attributes["summary1"] != nil || attributes["summary2"] != nil { report.record(.summary) }
        items.append(OutlineDraft.Item(
            depth: depth,
            title: attributes["text"] ?? "",
            note: notes.isEmpty ? nil : notes.joined(separator: "\n\n"),
            link: link
        ))
        styles.append(FreeMindMap.Style(
            fileID: attributes["uuid"],
            color: attributes["color"].flatMap { FreeMindMap.paletteColor("#" + $0) }
        ))
    }
}
