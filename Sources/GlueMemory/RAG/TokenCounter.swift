/// Simple word-based token estimation.
/// Approximates 1 token ≈ 0.75 words (or ~4 characters).
public enum TokenCounter: Sendable {
    /// Estimate the token count for a string using word-based heuristic.
    public static func count(_ text: String) -> Int {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        // Rough approximation: 1 word ≈ 1.33 tokens
        return max(1, Int(Double(words.count) * 1.33))
    }
}
