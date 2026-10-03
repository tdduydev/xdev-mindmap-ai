import SwiftUI
import WidgetKit

@main
struct MindMapWatchWidgets: WidgetBundle {
    var body: some Widget {
        AddIdeaWidget()
    }
}

/// FR-WCH-03: a complication and Smart Stack card that opens the capture
/// screen. Static: it shows no map content, so it needs no App Group and no
/// timeline reloads.
struct AddIdeaWidget: Widget {
    /// The watch app's capture link (`WatchLink.capture` there).
    static let captureURL = URL(string: "mindmapai-watch://capture")!

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "asia.xdev.mindmapai.watch.addIdea", provider: AddIdeaProvider()) { _ in
            AddIdeaWidgetView()
                .widgetURL(Self.captureURL)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Add Idea")
        .description("Add an idea to your Inbox map.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct AddIdeaEntry: TimelineEntry {
    let date: Date
}

struct AddIdeaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AddIdeaEntry { AddIdeaEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (AddIdeaEntry) -> Void) {
        completion(AddIdeaEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AddIdeaEntry>) -> Void) {
        completion(Timeline(entries: [AddIdeaEntry(date: .now)], policy: .never))
    }
}

struct AddIdeaWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "plus.bubble")
                .widgetLabel("Add Idea")
        case .accessoryInline:
            Label("Add Idea", systemImage: "plus.bubble")
        case .accessoryRectangular:
            HStack {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("Add Idea")
                        .font(.headline)
                        .widgetAccentable()
                    Text("MindMap AI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus.bubble")
                    .font(.title3)
                    .widgetAccentable()
            }
            .accessibilityLabel("Add Idea")
        }
    }
}
