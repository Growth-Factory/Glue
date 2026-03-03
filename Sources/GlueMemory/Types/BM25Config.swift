/// Configuration for BM25 text search parameters.
public struct BM25Config: Sendable, Equatable {
    /// Term frequency saturation parameter. Higher values increase the impact of term frequency.
    public var k1: Double

    /// Length normalization parameter (0 = no normalization, 1 = full normalization).
    public var b: Double

    public init(k1: Double = 1.2, b: Double = 0.75) {
        self.k1 = k1
        self.b = b
    }
}
