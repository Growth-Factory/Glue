/// How to execute a search query.
public enum SearchMode: Sendable, Codable, Equatable {
    /// Full-text search only (BM25/tsvector).
    case textOnly
    /// Vector similarity search only.
    case vectorOnly
    /// Hybrid search combining text and vector results.
    /// `alpha` controls the weighting: 0.0 = text only, 1.0 = vector only.
    case hybrid(alpha: Float)

    public static var hybrid: SearchMode { .hybrid(alpha: 0.5) }
}
