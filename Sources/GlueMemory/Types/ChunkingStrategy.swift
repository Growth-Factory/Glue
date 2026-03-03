/// Strategy for splitting text into chunks.
public enum ChunkingStrategy: Sendable {
    /// Split by approximate token count with overlap.
    case tokenCount(targetTokens: Int, overlapTokens: Int)

    public static var `default`: ChunkingStrategy {
        .tokenCount(targetTokens: 256, overlapTokens: 32)
    }
}
