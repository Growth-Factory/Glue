/// Configuration for the vector similarity index type.
public enum VectorIndexType: Sendable, Equatable {
    /// IVFFlat index — fast builds, good for smaller datasets.
    case ivfflat(lists: Int)

    /// HNSW index — better recall, recommended for most workloads.
    case hnsw(m: Int, efConstruction: Int)

    /// Default: HNSW with standard parameters.
    public static var `default`: VectorIndexType {
        .hnsw(m: 16, efConstruction: 64)
    }
}
