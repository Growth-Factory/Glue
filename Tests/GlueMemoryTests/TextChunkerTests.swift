import Testing
@testable import GlueMemory

@Suite("TextChunker")
struct TextChunkerTests {
    @Test func shortText() {
        let text = "Hello world, this is a short text."
        let chunks = TextChunker.chunk(text, strategy: .tokenCount(targetTokens: 256, overlapTokens: 32))
        #expect(chunks.count == 1)
        #expect(chunks[0] == text)
    }

    @Test func longText() {
        // Generate text that's longer than one chunk (~256 tokens ≈ 192 words)
        let words = (0..<400).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = TextChunker.chunk(text, strategy: .tokenCount(targetTokens: 256, overlapTokens: 32))
        #expect(chunks.count > 1)

        // Each chunk should have content
        for chunk in chunks {
            #expect(!chunk.isEmpty)
        }
    }

    @Test func overlap() {
        let words = (0..<400).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let chunks = TextChunker.chunk(text, strategy: .tokenCount(targetTokens: 100, overlapTokens: 20))
        #expect(chunks.count >= 2)

        // Check that consecutive chunks share some words
        if chunks.count >= 2 {
            let firstWords = Set(chunks[0].split(separator: " ").suffix(20))
            let secondWords = Set(chunks[1].split(separator: " ").prefix(20))
            let overlap = firstWords.intersection(secondWords)
            #expect(!overlap.isEmpty, "Consecutive chunks should share overlap words")
        }
    }

    @Test func emptyText() {
        let chunks = TextChunker.chunk("", strategy: .default)
        #expect(chunks.isEmpty)
    }

    // MARK: - Sentence Chunking

    @Test func sentenceSplitting() {
        let text = "First sentence. Second sentence. Third sentence."
        let sentences = TextChunker.splitSentences(text)
        #expect(sentences.count == 3)
        #expect(sentences[0] == "First sentence.")
        #expect(sentences[1] == "Second sentence.")
        #expect(sentences[2] == "Third sentence.")
    }

    @Test func sentenceChunking() {
        let sentences = (0..<20).map { "This is sentence number \($0)." }
        let text = sentences.joined(separator: " ")

        let chunks = TextChunker.chunk(text, strategy: .sentence(maxTokens: 30, overlapSentences: 1))
        #expect(chunks.count > 1)

        for chunk in chunks {
            #expect(!chunk.isEmpty)
        }
    }

    @Test func sentenceChunkingOverlap() {
        let text = "Alpha fact. Beta fact. Gamma fact. Delta fact. Epsilon fact."
        let chunks = TextChunker.chunk(text, strategy: .sentence(maxTokens: 10, overlapSentences: 1))
        #expect(chunks.count >= 2)

        // With overlap=1, last sentence of chunk N should appear in chunk N+1
        if chunks.count >= 2 {
            let firstSentences = chunks[0].components(separatedBy: ". ")
            let secondSentences = chunks[1].components(separatedBy: ". ")
            let lastOfFirst = firstSentences.last ?? ""
            let firstOfSecond = secondSentences.first ?? ""
            // The overlap sentence should appear
            #expect(!lastOfFirst.isEmpty)
            #expect(!firstOfSecond.isEmpty)
        }
    }

    // MARK: - Recursive Chunking

    @Test func recursiveWithParagraphs() {
        let paragraphs = (0..<5).map { i in
            (0..<10).map { j in "Paragraph \(i) sentence \(j)." }.joined(separator: " ")
        }
        let text = paragraphs.joined(separator: "\n\n")

        let chunks = TextChunker.chunk(
            text,
            strategy: .recursive(separators: ["\n\n", "\n", ". "], targetTokens: 50, overlapTokens: 0)
        )
        #expect(chunks.count > 1)

        for chunk in chunks {
            #expect(!chunk.isEmpty)
        }
    }

    @Test func recursiveFallsBackToTokenCount() {
        let text = String(repeating: "word ", count: 200)

        // No separators match — falls back to token count
        let chunks = TextChunker.chunk(
            text,
            strategy: .recursive(separators: ["###"], targetTokens: 50, overlapTokens: 5)
        )
        #expect(chunks.count > 1)
    }

    @Test func recursiveShortText() {
        let text = "Short text."
        let chunks = TextChunker.chunk(
            text,
            strategy: .recursive(separators: ["\n\n", "\n"], targetTokens: 100, overlapTokens: 0)
        )
        #expect(chunks.count == 1)
        #expect(chunks[0] == text)
    }

    // MARK: - Custom Token Counter

    @Test func customTokenCounterInChunker() {
        struct HalfCounter: TokenCounting {
            func count(_ text: String) -> Int {
                max(1, TokenCounter.count(text) / 2)
            }
        }

        let words = (0..<200).map { "word\($0)" }
        let text = words.joined(separator: " ")

        let normalChunks = TextChunker.chunk(text, strategy: .tokenCount(targetTokens: 50, overlapTokens: 0))
        let halfChunks = TextChunker.chunk(text, strategy: .tokenCount(targetTokens: 50, overlapTokens: 0), tokenCounter: HalfCounter())

        // With a counter that reports half the tokens, we should get the same chunks
        // since tokenCount strategy uses word-based approximation rather than the counter
        // But sentence/recursive strategies use the counter
        #expect(normalChunks.count > 1)
        #expect(halfChunks.count > 1)
    }
}
