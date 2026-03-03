/// A request to search stored memories.
public struct SearchRequest: Sendable {
    public let query: String
    public let mode: SearchMode
    public let topK: Int
    public let minScore: Float?

    public init(
        query: String,
        mode: SearchMode = .hybrid,
        topK: Int = 10,
        minScore: Float? = nil
    ) {
        self.query = query
        self.mode = mode
        self.topK = topK
        self.minScore = minScore
    }
}
