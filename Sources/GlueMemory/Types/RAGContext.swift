/// Assembled context for retrieval-augmented generation.
public struct RAGContext: Sendable {
    public let query: String
    public let items: [RAGContextItem]
    public let totalTokens: Int

    public init(query: String, items: [RAGContextItem], totalTokens: Int) {
        self.query = query
        self.items = items
        self.totalTokens = totalTokens
    }

    /// Renders all items into a single context string.
    public var rendered: String {
        items.map(\.content).joined(separator: "\n\n")
    }
}

/// A single item in a RAG context.
public struct RAGContextItem: Sendable {
    public let content: String
    public let score: Float
    public let tokenCount: Int

    public init(content: String, score: Float, tokenCount: Int) {
        self.content = content
        self.score = score
        self.tokenCount = tokenCount
    }
}
