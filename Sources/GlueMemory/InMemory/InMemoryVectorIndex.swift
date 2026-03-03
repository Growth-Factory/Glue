import Foundation

/// Brute-force cosine similarity vector search for in-memory use.
public actor InMemoryVectorIndex: Sendable {
    private var vectors: [UUID: [Float]] = [:]

    public init() {}

    public func index(frameId: UUID, embedding: [Float]) {
        vectors[frameId] = embedding
    }

    public func remove(frameId: UUID) {
        vectors.removeValue(forKey: frameId)
    }

    public func search(query: [Float], topK: Int) -> [(UUID, Float)] {
        guard !vectors.isEmpty else { return [] }

        var scores: [(UUID, Float)] = []
        for (id, vector) in vectors {
            let similarity = cosineSimilarity(query, vector)
            if similarity > 0 {
                scores.append((id, similarity))
            }
        }

        scores.sort { $0.1 > $1.1 }
        return Array(scores.prefix(topK))
    }

    // MARK: - Private

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }
}
