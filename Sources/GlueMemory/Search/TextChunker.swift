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

    /// Common abbreviations that should NOT trigger a sentence split.
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st",
        "inc", "ltd", "co", "corp", "dept", "univ",
        "vs", "etc", "approx", "est", "vol", "no",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
        "fig", "eq", "ref", "sec", "ch", "pg",
    ]

    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            current.append(ch)

            if ch == "." || ch == "!" || ch == "?" {
                // Look ahead: is there whitespace followed by an uppercase letter or end?
                let nextIdx = i + 1
                guard nextIdx < chars.count, chars[nextIdx].isWhitespace else {
                    i += 1
                    continue
                }

                // Check for abbreviation before the period
                if ch == "." {
                    // Extract word before the dot
                    let trimmed = current.dropLast() // remove the dot
                    if let lastSpace = trimmed.lastIndex(where: { $0.isWhitespace || $0 == "(" }) {
                        let word = String(trimmed[trimmed.index(after: lastSpace)...]).lowercased()
                        if abbreviations.contains(word) { i += 1; continue }
                    } else {
                        let word = String(trimmed).lowercased()
                        if abbreviations.contains(word) { i += 1; continue }
                    }

                    // Skip decimal numbers: digit before dot, digit after whitespace-skip
                    if let prev = trimmed.last, prev.isNumber {
                        // Look past whitespace for digit
                        var peek = nextIdx
                        while peek < chars.count && chars[peek].isWhitespace { peek += 1 }
                        if peek < chars.count && chars[peek].isNumber { i += 1; continue }
                    }

                    // Single uppercase letter (initials like "U.S.")
                    if trimmed.count >= 1 {
                        let beforeDot = trimmed.last!
                        if beforeDot.isUppercase && (trimmed.count == 1 || trimmed[trimmed.index(trimmed.endIndex, offsetBy: -2)].isWhitespace || trimmed[trimmed.index(trimmed.endIndex, offsetBy: -2)] == ".") {
                            i += 1; continue
                        }
                    }
                }

                // This looks like a real sentence boundary
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                current = ""
            }
            i += 1
        }

        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty { sentences.append(remaining) }

        return sentences.isEmpty ? [text] : sentences
    }
}

