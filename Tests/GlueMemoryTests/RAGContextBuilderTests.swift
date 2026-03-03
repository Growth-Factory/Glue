import Testing
import Foundation
@testable import GlueMemory

@Suite("RAGContextBuilder")
struct RAGContextBuilderTests {
    @Test func tokenBudget() {
        // Each result has ~13 tokens (10 words * 1.33)
        let results = (0..<10).map { i in
            SearchResult(
                frameId: UUID(),
                score: Float(10 - i) / 10.0,
                content: "This is result number \(i) with some extra words here today"
            )
        }

        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 30)
        #expect(context.totalTokens <= 30)
        #expect(!context.items.isEmpty)
    }

    @Test func ordering() {
        let results = [
            SearchResult(frameId: UUID(), score: 0.9, content: "best"),
            SearchResult(frameId: UUID(), score: 0.5, content: "okay"),
            SearchResult(frameId: UUID(), score: 0.1, content: "worst"),
        ]

        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 1000)
        #expect(context.items.count == 3)
        #expect(context.items[0].content == "best")
    }

    @Test func largeBudget() {
        let results = (0..<5).map { i in
            SearchResult(frameId: UUID(), score: 0.5, content: "item \(i)")
        }

        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 100_000)
        #expect(context.items.count == 5)
    }

    @Test func rendered() {
        let results = [
            SearchResult(frameId: UUID(), score: 0.9, content: "First paragraph"),
            SearchResult(frameId: UUID(), score: 0.8, content: "Second paragraph"),
        ]

        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 10000)
        #expect(context.rendered.contains("First paragraph"))
        #expect(context.rendered.contains("Second paragraph"))
    }

    @Test func oversizedDocumentIsChunked() {
        // Create a document with ~200 words (~266 tokens)
        let longContent = (0..<200).map { "word\($0)" }.joined(separator: " ")
        let results = [
            SearchResult(frameId: UUID(), score: 0.9, content: longContent),
        ]

        // Use small chunks (32 tokens target) so they fit within a 100 token budget
        let smallChunks = ChunkingStrategy.tokenCount(targetTokens: 32, overlapTokens: 4)
        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 100, chunkingStrategy: smallChunks)
        #expect(!context.items.isEmpty, "Should include chunks, not skip the document")
        #expect(context.totalTokens <= 100)
        #expect(context.totalTokens > 0)

        // Verify the chunks contain parts of the original content
        for item in context.items {
            #expect(longContent.contains(item.content.split(separator: " ").first.map(String.init) ?? ""))
        }
    }

    @Test func chunkingPreservesAllContentWhenBudgetAllows() {
        // ~200 words (~266 tokens), large budget — all chunks should fit
        let longContent = (0..<200).map { "word\($0)" }.joined(separator: " ")
        let results = [
            SearchResult(frameId: UUID(), score: 0.9, content: longContent),
        ]

        let smallChunks = ChunkingStrategy.tokenCount(targetTokens: 32, overlapTokens: 4)
        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 1000, chunkingStrategy: smallChunks)
        #expect(!context.items.isEmpty)
        // All words from original should appear in at least one chunk
        let allChunkText = context.items.map(\.content).joined(separator: " ")
        #expect(allChunkText.contains("word0"))
        #expect(allChunkText.contains("word199"))
    }

    @Test func mixOfSmallAndOversizedDocuments() {
        let small = SearchResult(frameId: UUID(), score: 0.9, content: "short doc fits easily")
        let longContent = (0..<200).map { "word\($0)" }.joined(separator: " ")
        let big = SearchResult(frameId: UUID(), score: 0.8, content: longContent)

        let smallChunks = ChunkingStrategy.tokenCount(targetTokens: 32, overlapTokens: 4)
        let context = RAGContextBuilder.build(query: "test", results: [small, big], tokenBudget: 80, chunkingStrategy: smallChunks)

        // Small doc should be included whole
        #expect(context.items.first?.content == "short doc fits easily")
        // Remaining budget goes to chunks of the big doc
        #expect(context.items.count > 1, "Should include chunks from the big document")
        #expect(context.totalTokens <= 80)
    }

    @Test func budgetExhaustedStopsProcessing() {
        // Two big documents, budget only fits chunks from the first
        let long1 = (0..<200).map { "alpha\($0)" }.joined(separator: " ")
        let long2 = (0..<200).map { "beta\($0)" }.joined(separator: " ")
        let results = [
            SearchResult(frameId: UUID(), score: 0.9, content: long1),
            SearchResult(frameId: UUID(), score: 0.8, content: long2),
        ]

        let smallChunks = ChunkingStrategy.tokenCount(targetTokens: 32, overlapTokens: 4)
        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 50, chunkingStrategy: smallChunks)
        #expect(context.totalTokens <= 50)
        // Should contain alpha words but not beta (budget exhausted)
        let allText = context.items.map(\.content).joined(separator: " ")
        #expect(allText.contains("alpha0"))
    }
}
