import Foundation

/// A result from a text-only search.
public struct TextSearchResult: Sendable, Equatable {
    public let frameId: UUID
    public let score: Float
    public let snippet: String
    public let metadata: [String: String]

    public init(frameId: UUID, score: Float, snippet: String, metadata: [String: String] = [:]) {
        self.frameId = frameId
        self.score = score
        self.snippet = snippet
        self.metadata = metadata
    }
}
