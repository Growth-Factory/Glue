/// Provides text embeddings from an external model.
public protocol EmbeddingProvider: Sendable {
    /// Generate an embedding vector for the given text.
    func embed(_ text: String) async throws -> [Float]

    /// The dimensionality of the embedding vectors.
    var dimensions: Int { get }

    /// Whether to L2-normalize returned vectors.
    var normalize: Bool { get }

    /// Identity of the embedding model (provider + model + dimensions).
    var identity: EmbeddingIdentity { get }
}
