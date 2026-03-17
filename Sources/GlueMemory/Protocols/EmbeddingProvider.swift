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
    /// Default: calls `embed()` concurrently for all texts.
    /// Providers should override with a native batch API for best performance.
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        if texts.count == 1 { return [try await embed(texts[0])] }

        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (i, text) in texts.enumerated() {
                group.addTask { (i, try await self.embed(text)) }
            }
            var results = Array<[Float]?>(repeating: nil, count: texts.count)
            for try await (i, vec) in group { results[i] = vec }
            return results.map { $0! }
        }
    }
}
