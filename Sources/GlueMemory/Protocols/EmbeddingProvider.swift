/// Provides text embeddings from an external model.
public protocol EmbeddingProvider: Sendable {
    /// Generate an embedding vector for the given text.
    func embed(_ text: String) async throws -> [Float]

    /// Generate embedding vectors for multiple texts in a single batch.
    /// Default implementation calls `embed()` for each text sequentially.
    func embedBatch(_ texts: [String]) async throws -> [[Float]]

    /// The dimensionality of the embedding vectors.
    var dimensions: Int { get }

    /// Whether to L2-normalize returned vectors.
    var normalize: Bool { get }

    /// Identity of the embedding model (provider + model + dimensions).
    var identity: EmbeddingIdentity { get }
}

extension EmbeddingProvider {
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            results.append(try await embed(text))
        }
        return results
    }
}
