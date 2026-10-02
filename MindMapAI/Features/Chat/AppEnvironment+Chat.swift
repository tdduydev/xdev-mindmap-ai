import MindMapQuery

extension AppEnvironment {
    /// The reads the chat's tools make, through the same `OpenMapsGraphSource`
    /// as AI apps: an open map answers from the editor's live graph.
    var mapQueries: MapQueries {
        MapQueries(repository: repository, graphs: OpenMapsGraphSource(openMaps: openMaps, repository: repository))
    }
}
