/// Strategy for splitting text into chunks.
public enum ChunkingStrategy: Sendable {
    /// Split by approximate token count with overlap.
    case tokenCount(targetTokens: Int, overlapTokens: Int)

    /// Split on sentence boundaries, accumulating until token budget is reached.
    case sentence(maxTokens: Int, overlapSentences: Int)

    /// Hierarchical splitting: try separators in order, recurse if chunks are too large.
    case recursive(separators: [String], targetTokens: Int, overlapTokens: Int)

    public static var `default`: ChunkingStrategy {
        .tokenCount(targetTokens: 256, overlapTokens: 32)
    }
}
