import Foundation

extension MapTools {
    /// `tools/list`, in a fixed order: 2026-07-28 asks for a deterministic list
    /// so clients can cache it. Descriptions are for the model, in English like
    /// the protocol; the person never sees them in the app.
    static let definitions: [JSONValue] = [
        tool(
            "list_maps", title: "List Maps",
            description: "List the person's mind maps in MindMap AI, most recently edited first, with each map's map_id, title, topic count and last edit. Maps in Recently Deleted are never listed.",
            properties: [
                "query": ["type": "string", "description": "Only maps whose title contains these words. Matching ignores case and Vietnamese diacritics."],
                "limit": ["type": "integer", "minimum": 1, "maximum": 200, "default": 50, "description": "Most maps to return."],
            ]
        ),
        tool(
            "get_map", title: "Get Map Outline",
            description: "Read a map, or one branch of it, as a Markdown outline from the central topic down, with each topic's topic_id in a comment and its note under it. Long maps are cut; the end says how many topics were left out, and get_map with topic_id and depth reads them.",
            properties: [
                "map_id": ["type": "string", "description": "A map_id from list_maps or search."],
                "topic_id": ["type": "string", "description": "Start at this topic instead of the central topic."],
                "depth": ["type": "integer", "minimum": 0, "description": "Levels below the starting topic to include; 0 is the starting topic alone. Omit for every level."],
                "include_notes": ["type": "boolean", "default": true, "description": "Include topic notes."],
            ],
            required: ["map_id"]
        ),
        tool(
            "search", title: "Search Topics",
            description: "Find topics whose title or note contains every word of the query, across all maps or in one map. Title matches come first. Each hit has its map_id, topic_id, the path from the central topic and, for a note match, a short excerpt. Matching ignores case and Vietnamese diacritics.",
            properties: [
                "query": ["type": "string", "description": "Words to find."],
                "map_id": ["type": "string", "description": "Search only this map."],
                "limit": ["type": "integer", "minimum": 1, "maximum": 50, "default": 20, "description": "Most topics to return."],
            ],
            required: ["query"]
        ),
        tool(
            "get_topic", title: "Get Topic",
            description: "Everything about one topic: title, full note, path from the central topic, subtopics, tags, task state, priority, dates and cross-links to other topics.",
            properties: [
                "map_id": ["type": "string", "description": "The topic's map_id."],
                "topic_id": ["type": "string", "description": "A topic_id from get_map or search."],
            ],
            required: ["map_id", "topic_id"]
        ),
    ]

    private static func tool(
        _ name: String,
        title: String,
        description: String,
        properties: [String: JSONValue],
        required: [String] = []
    ) -> JSONValue {
        var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties), "additionalProperties": false]
        if !required.isEmpty { schema["required"] = .array(required.map(JSONValue.string)) }
        return [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": .object(schema),
            // Hints only: clients must not trust them, but they let a client skip
            // its confirmation prompt for reads.
            "annotations": [
                "title": .string(title),
                "readOnlyHint": true,
                "destructiveHint": false,
                "idempotentHint": true,
                "openWorldHint": false,
            ],
        ]
    }
}
