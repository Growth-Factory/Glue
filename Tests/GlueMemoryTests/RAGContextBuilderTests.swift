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
}
