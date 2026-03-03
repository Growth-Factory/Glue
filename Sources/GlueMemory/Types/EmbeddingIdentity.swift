/// Identifies the embedding model to ensure consistency.
public struct EmbeddingIdentity: Sendable, Codable, Hashable {
    public let provider: String
    public let model: String
    public let dimensions: Int

    public init(provider: String, model: String, dimensions: Int) {
        self.provider = provider
        self.model = model
        self.dimensions = dimensions
    }
}
