/// A request to search stored memories.
public struct SearchRequest: Sendable {
    public let query: String
    public let mode: SearchMode
    public let topK: Int
    public let minScore: Float?
    public let filters: [MetadataFilter]?

    public init(
        query: String,
        mode: SearchMode = .hybrid,
        topK: Int = 10,
        minScore: Float? = nil,
        filters: [MetadataFilter]? = nil
    ) {
        self.query = query
        self.mode = mode
        self.topK = topK
        self.minScore = minScore
        self.filters = filters
    }
}
