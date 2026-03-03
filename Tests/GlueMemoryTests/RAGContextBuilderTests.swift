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
        let frameId = UUID()
        let results = [
            SearchResult(frameId: frameId, score: 0.9, content: longContent),
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
            #expect(item.sourceFrameId == frameId)
            #expect(item.isChunk)
            #expect(item.chunkIndex != nil)
            #expect(item.totalChunksInSource != nil)
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

    // MARK: - Source tracking tests

    @Test func sourceFrameIdTracking() {
        let id1 = UUID()
        let id2 = UUID()
        let results = [
            SearchResult(frameId: id1, score: 0.9, content: "first"),
            SearchResult(frameId: id2, score: 0.8, content: "second"),
        ]

        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 1000)
        #expect(context.items[0].sourceFrameId == id1)
        #expect(context.items[1].sourceFrameId == id2)
        #expect(!context.items[0].isChunk)
        #expect(!context.items[1].isChunk)
        #expect(context.items[0].chunkIndex == nil)
        #expect(context.items[1].chunkIndex == nil)
    }

    @Test func chunkSourceTracking() {
        let frameId = UUID()
        // ~200 words = ~266 tokens, budget 100 forces chunking
        let longContent = (0..<200).map { "word\($0)" }.joined(separator: " ")
        let results = [
            SearchResult(frameId: frameId, score: 0.9, content: longContent),
        ]

        let smallChunks = ChunkingStrategy.tokenCount(targetTokens: 32, overlapTokens: 4)
        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 100, chunkingStrategy: smallChunks)

        #expect(!context.items.isEmpty)
        for (index, item) in context.items.enumerated() {
            #expect(item.sourceFrameId == frameId)
            #expect(item.isChunk)
            #expect(item.chunkIndex == index)
            #expect(item.totalChunksInSource != nil)
        }
    }

    // MARK: - Overflow metadata tests

    @Test func overflowIsCompleteWhenEverythingFits() {
        let results = [
            SearchResult(frameId: UUID(), score: 0.9, content: "short"),
            SearchResult(frameId: UUID(), score: 0.8, content: "also short"),
        ]

        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 1000)
        #expect(context.overflow.isComplete)
        #expect(context.overflow.totalResultsProvided == 2)
        #expect(context.overflow.resultsIncluded == 2)
        #expect(context.overflow.resultsDropped == 0)
        #expect(context.overflow.droppedResults.isEmpty)
    }

    @Test func overflowTracksDroppedResults() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let results = [
            SearchResult(frameId: id1, score: 0.9, content: "fits fine"),
            SearchResult(frameId: id2, score: 0.5, content: "This one has many more words and will not fit in the tiny budget"),
            SearchResult(frameId: id3, score: 0.3, content: "Another result that also will not fit in the tiny budget at all"),
        ]

        // Budget fits the first result only
        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 5)
        #expect(!context.overflow.isComplete)
        #expect(context.overflow.totalResultsProvided == 3)
        #expect(context.overflow.resultsIncluded == 1)
        #expect(context.overflow.resultsDropped == 2)
        #expect(context.overflow.droppedResults.count == 2)
        #expect(context.overflow.droppedResults[0].frameId == id2)
        #expect(context.overflow.droppedResults[1].frameId == id3)
        #expect(context.overflow.droppedResults[0].score == 0.5)
        #expect(context.overflow.droppedResults[1].score == 0.3)
        #expect(context.overflow.droppedResults[0].estimatedTokens > 0)
    }

    @Test func partialChunkInclusion() {
        // A document that must be chunked — some chunks fit, rest are dropped
        let frameId = UUID()
        let longContent = (0..<200).map { "word\($0)" }.joined(separator: " ")
        let results = [
            SearchResult(frameId: frameId, score: 0.9, content: longContent),
        ]

        let smallChunks = ChunkingStrategy.tokenCount(targetTokens: 32, overlapTokens: 4)
        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 50, chunkingStrategy: smallChunks)

        // Some chunks included
        #expect(!context.items.isEmpty)
        #expect(context.totalTokens <= 50)

        // Frame is counted as included (partial inclusion)
        #expect(context.overflow.resultsIncluded == 1)
        // Not counted as dropped since at least some content was included
        #expect(context.overflow.resultsDropped == 0)
        #expect(context.overflow.droppedResults.isEmpty)
    }

    @Test func allResultsDroppedWhenBudgetZero() {
        let id1 = UUID()
        let id2 = UUID()
        let results = [
            SearchResult(frameId: id1, score: 0.9, content: "something"),
            SearchResult(frameId: id2, score: 0.5, content: "else"),
        ]

        let context = RAGContextBuilder.build(query: "test", results: results, tokenBudget: 0)
        #expect(context.items.isEmpty)
        #expect(context.overflow.totalResultsProvided == 2)
        #expect(context.overflow.resultsIncluded == 0)
        #expect(context.overflow.resultsDropped == 2)
        #expect(!context.overflow.isComplete)
    }
}
