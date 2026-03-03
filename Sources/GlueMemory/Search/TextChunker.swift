/// Token-aware text splitter with configurable overlap.
public enum TextChunker: Sendable {
    /// Split text into chunks according to the given strategy.
    public static func chunk(_ text: String, strategy: ChunkingStrategy) -> [String] {
        switch strategy {
        case .tokenCount(let targetTokens, let overlapTokens):
            return chunkByTokenCount(text, targetTokens: targetTokens, overlapTokens: overlapTokens)
        }
    }

    private static func chunkByTokenCount(_ text: String, targetTokens: Int, overlapTokens: Int) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        guard !words.isEmpty else { return [] }

        // Approximate: 1 word ≈ 1.33 tokens → targetTokens tokens ≈ targetTokens/1.33 words
        let wordsPerChunk = max(1, Int(Double(targetTokens) / 1.33))
        let overlapWords = max(0, Int(Double(overlapTokens) / 1.33))

        guard words.count > wordsPerChunk else {
            return [text]
        }

        var chunks: [String] = []
        var start = 0

        while start < words.count {
            let end = min(start + wordsPerChunk, words.count)
            let chunk = words[start..<end].joined(separator: " ")
            chunks.append(chunk)

            if end >= words.count { break }
            start = end - overlapWords
        }

        return chunks
    }
}
