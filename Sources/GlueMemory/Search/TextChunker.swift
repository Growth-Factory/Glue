import Foundation

/// Token-aware text splitter with configurable overlap.
public enum TextChunker: Sendable {
    /// Split text into chunks according to the given strategy.
    public static func chunk(
        _ text: String,
        strategy: ChunkingStrategy,
        tokenCounter: (any TokenCounting)? = nil
    ) -> [String] {
        let counter = tokenCounter ?? TokenCounter()
        switch strategy {
        case .tokenCount(let targetTokens, let overlapTokens):
            return chunkByTokenCount(text, targetTokens: targetTokens, overlapTokens: overlapTokens, counter: counter)
        case .sentence(let maxTokens, let overlapSentences):
            return chunkBySentence(text, maxTokens: maxTokens, overlapSentences: overlapSentences, counter: counter)
        case .recursive(let separators, let targetTokens, let overlapTokens):
            return chunkRecursive(text, separators: separators, targetTokens: targetTokens, overlapTokens: overlapTokens, counter: counter)
        }
    }

    // MARK: - Token Count Strategy

    private static func chunkByTokenCount(
        _ text: String,
        targetTokens: Int,
        overlapTokens: Int,
        counter: any TokenCounting
    ) -> [String] {
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

    // MARK: - Sentence Strategy

    private static func chunkBySentence(
        _ text: String,
        maxTokens: Int,
        overlapSentences: Int,
        counter: any TokenCounting
    ) -> [String] {
        let sentences = splitSentences(text)
        guard !sentences.isEmpty else { return [] }
        guard sentences.count > 1 else { return [text] }

        var chunks: [String] = []
        var currentSentences: [String] = []
        var currentTokens = 0

        for sentence in sentences {
            let sentenceTokens = counter.count(sentence)

            if !currentSentences.isEmpty && currentTokens + sentenceTokens > maxTokens {
                chunks.append(currentSentences.joined(separator: " "))
                // Keep overlap sentences
                let overlapCount = min(overlapSentences, currentSentences.count)
                let kept = Array(currentSentences.suffix(overlapCount))
                currentSentences = kept
                currentTokens = kept.reduce(0) { $0 + counter.count($1) }
            }

            currentSentences.append(sentence)
            currentTokens += sentenceTokens
        }

        if !currentSentences.isEmpty {
            chunks.append(currentSentences.joined(separator: " "))
        }

        return chunks
    }

    // MARK: - Recursive Strategy

    private static func chunkRecursive(
        _ text: String,
        separators: [String],
        targetTokens: Int,
        overlapTokens: Int,
        counter: any TokenCounting
    ) -> [String] {
        guard counter.count(text) > targetTokens else {
            return [text]
        }

        guard let separator = separators.first else {
            // No more separators — fall back to token count
            return chunkByTokenCount(text, targetTokens: targetTokens, overlapTokens: overlapTokens, counter: counter)
        }

        let parts = text.components(separatedBy: separator).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard parts.count > 1 else {
            // Separator didn't split — try next
            return chunkRecursive(text, separators: Array(separators.dropFirst()), targetTokens: targetTokens, overlapTokens: overlapTokens, counter: counter)
        }

        var chunks: [String] = []
        var currentParts: [String] = []
        var currentTokens = 0

        for part in parts {
            let partTokens = counter.count(part)

            if !currentParts.isEmpty && currentTokens + partTokens > targetTokens {
                let merged = currentParts.joined(separator: separator)
                // If merged chunk is still too large, recurse with remaining separators
                if counter.count(merged) > targetTokens {
                    chunks.append(contentsOf: chunkRecursive(merged, separators: Array(separators.dropFirst()), targetTokens: targetTokens, overlapTokens: overlapTokens, counter: counter))
                } else {
                    chunks.append(merged)
                }
                currentParts = []
                currentTokens = 0
            }

            currentParts.append(part)
            currentTokens += partTokens
        }

        if !currentParts.isEmpty {
            let merged = currentParts.joined(separator: separator)
            if counter.count(merged) > targetTokens {
                chunks.append(contentsOf: chunkRecursive(merged, separators: Array(separators.dropFirst()), targetTokens: targetTokens, overlapTokens: overlapTokens, counter: counter))
            } else {
                chunks.append(merged)
            }
        }

        return chunks
    }

    // MARK: - Helpers

    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let pattern = "(?<=[.!?])\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let nsText = text as NSString
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let sentence = nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            lastEnd = match.range.location + match.range.length
        }

        // Remaining text
        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                sentences.append(remaining)
            }
        }

        return sentences
    }
}

