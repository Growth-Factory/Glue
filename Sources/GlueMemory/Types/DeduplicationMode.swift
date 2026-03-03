/// Controls how duplicate content is handled during ingestion.
public enum DeduplicationMode: Sendable, Equatable {
    /// No deduplication — duplicates are stored as separate frames.
    case none

    /// Skip duplicates — return the existing frame without storing.
    case skip

    /// Replace duplicates — update the existing frame with new metadata.
    case replace
}
