import Foundation

/// A single search result item.
public struct SearchResult: Sendable, Equatable {
    public let frameId: UUID
    public let score: Float
    public let content: String

    public init(frameId: UUID, score: Float, content: String) {
        self.frameId = frameId
        self.score = score
        self.content = content
    }
}

/// The response from a search operation.
public struct SearchResponse: Sendable {
    public let results: [SearchResult]
    public let query: String

    public init(results: [SearchResult], query: String) {
        self.results = results
        self.query = query
    }
}
