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
}
