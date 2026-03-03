/// Improved word-based token estimation.
/// Uses length-aware heuristics: short words map to 1 token, longer words
/// scale by length, punctuation and numbers each count as 1 token.
public struct TokenCounter: TokenCounting, Sendable {
    public init() {}

    /// Instance method conforming to `TokenCounting`.
    public func count(_ text: String) -> Int {
        Self.count(text)
    }

    /// Static estimation for use without an instance.
    public static func count(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var tokens = 0
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if c.isWhitespace || c.isNewline {
                i = text.index(after: i)
                continue
            }

            if c.isPunctuation || c.isSymbol {
                tokens += 1
                i = text.index(after: i)
                continue
            }

            if c.isNumber {
                // Consume entire number run as 1 token
                tokens += 1
                i = text.index(after: i)
                while i < text.endIndex && text[i].isNumber {
                    i = text.index(after: i)
                }
                continue
            }

            // Word: consume alphanumeric characters
            let wordStart = i
            i = text.index(after: i)
            while i < text.endIndex && (text[i].isLetter || text[i].isNumber) {
                i = text.index(after: i)
            }
            let length = text.distance(from: wordStart, to: i)

            if length <= 4 {
                tokens += 1
            } else {
                tokens += 1 + (length - 4) / 4
            }
        }

        return max(1, tokens)
    }
}
