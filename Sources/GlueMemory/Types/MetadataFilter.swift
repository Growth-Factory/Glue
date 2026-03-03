/// Filter criteria for metadata-based search filtering.
public enum MetadataFilter: Sendable, Equatable {
    /// Exact match: metadata[key] == value
    case equals(key: String, value: String)

    /// Substring match: metadata[key] contains value
    case contains(key: String, value: String)

    /// Key existence: metadata has key
    case exists(key: String)
}
