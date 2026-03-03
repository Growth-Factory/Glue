import Foundation

/// Assembled context for retrieval-augmented generation.
public struct RAGContext: Sendable {
    public let query: String
    public let items: [RAGContextItem]
    public let totalTokens: Int
    public let overflow: Overflow

    public init(query: String, items: [RAGContextItem], totalTokens: Int, overflow: Overflow) {
        self.query = query
        self.items = items
        self.totalTokens = totalTokens
        self.overflow = overflow
    }

    /// Renders all items into a single context string.
    public var rendered: String {
        items.map(\.content).joined(separator: "\n\n")
    }
}

extension RAGContext {
    /// Metadata about results that could not fit within the token budget.
    public struct Overflow: Sendable {
        public let totalResultsProvided: Int
        public let resultsIncluded: Int
        public let resultsDropped: Int
        public let droppedResults: [DroppedResult]

        /// Whether all provided results fit within the budget.
        public var isComplete: Bool { resultsDropped == 0 }

        public init(
            totalResultsProvided: Int,
            resultsIncluded: Int,
            resultsDropped: Int,
            droppedResults: [DroppedResult]
        ) {
            self.totalResultsProvided = totalResultsProvided
            self.resultsIncluded = resultsIncluded
            self.resultsDropped = resultsDropped
            self.droppedResults = droppedResults
        }
    }

    /// A search result that was excluded from the context due to budget constraints.
    public struct DroppedResult: Sendable {
        public let frameId: UUID
        public let score: Float
        public let estimatedTokens: Int

        public init(frameId: UUID, score: Float, estimatedTokens: Int) {
            self.frameId = frameId
            self.score = score
            self.estimatedTokens = estimatedTokens
        }
    }
}

/// A single item in a RAG context.
public struct RAGContextItem: Sendable {
    public let content: String
    public let score: Float
    public let tokenCount: Int
    public let sourceFrameId: UUID
    public let isChunk: Bool
    public let chunkIndex: Int?
    public let totalChunksInSource: Int?

    public init(
        content: String,
        score: Float,
        tokenCount: Int,
        sourceFrameId: UUID,
        isChunk: Bool = false,
        chunkIndex: Int? = nil,
        totalChunksInSource: Int? = nil
    ) {
        self.content = content
        self.score = score
        self.tokenCount = tokenCount
        self.sourceFrameId = sourceFrameId
        self.isChunk = isChunk
        self.chunkIndex = chunkIndex
        self.totalChunksInSource = totalChunksInSource
    }
}
