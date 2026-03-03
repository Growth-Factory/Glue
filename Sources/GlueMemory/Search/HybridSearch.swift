import Foundation

/// Reciprocal Rank Fusion (RRF) for combining text and vector search results.
public enum HybridSearch: Sendable {
    /// Fuse text and vector search results using RRF.
    ///
    /// - Parameters:
    ///   - textResults: Results from text search, ordered by relevance.
    ///   - vectorResults: Results from vector search, ordered by relevance.
    ///   - alpha: Weight for vector results (0.0 = text only, 1.0 = vector only).
    ///   - topK: Maximum number of results to return.
    ///   - k: RRF constant (default 60).
    /// - Returns: Fused results sorted by combined score.
    public static func fuse(
        textResults: [TextSearchResult],
        vectorResults: [SearchResult],
        alpha: Float,
        topK: Int,
        k: Float = 60
    ) -> [SearchResult] {
        var scores: [UUID: (score: Float, content: String)] = [:]

        let textWeight = 1.0 - alpha
        let vectorWeight = alpha

        // Score text results by rank
        for (rank, result) in textResults.enumerated() {
            let rrfScore = textWeight / (k + Float(rank + 1))
            let existing = scores[result.frameId]
            scores[result.frameId] = (
                score: (existing?.score ?? 0) + rrfScore,
                content: existing?.content ?? result.snippet
            )
        }

        // Score vector results by rank
        for (rank, result) in vectorResults.enumerated() {
            let rrfScore = vectorWeight / (k + Float(rank + 1))
            let existing = scores[result.frameId]
            scores[result.frameId] = (
                score: (existing?.score ?? 0) + rrfScore,
                content: existing?.content ?? result.content
            )
        }

        var results = scores.map { (id, value) in
            SearchResult(frameId: id, score: value.score, content: value.content)
        }
        results.sort { $0.score > $1.score }
        return Array(results.prefix(topK))
    }
}
