import Testing
import Foundation
@testable import GlueMemory

@Suite("HybridSearch")
struct HybridSearchTests {
    @Test func textOnlyFusion() {
        let id1 = UUID()
        let id2 = UUID()

        let textResults = [
            TextSearchResult(frameId: id1, score: 2.0, snippet: "first"),
            TextSearchResult(frameId: id2, score: 1.0, snippet: "second"),
        ]

        let results = HybridSearch.fuse(
            textResults: textResults,
            vectorResults: [],
            alpha: 0.0,
            topK: 10
        )

        #expect(results.count == 2)
        #expect(results[0].frameId == id1, "Text-first result should rank first with alpha=0")
    }

    @Test func vectorOnlyFusion() {
        let id1 = UUID()
        let id2 = UUID()

        let vectorResults = [
            SearchResult(frameId: id1, score: 0.99, content: "first"),
            SearchResult(frameId: id2, score: 0.80, content: "second"),
        ]

        let results = HybridSearch.fuse(
            textResults: [],
            vectorResults: vectorResults,
            alpha: 1.0,
            topK: 10
        )

        #expect(results.count == 2)
        #expect(results[0].frameId == id1, "Vector-first result should rank first with alpha=1")
    }

    @Test func boostFromBothLists() {
        let sharedId = UUID()
        let textOnlyId = UUID()
        let vectorOnlyId = UUID()

        let textResults = [
            TextSearchResult(frameId: sharedId, score: 2.0, snippet: "shared"),
            TextSearchResult(frameId: textOnlyId, score: 1.5, snippet: "text only"),
        ]
        let vectorResults = [
            SearchResult(frameId: sharedId, score: 0.9, content: "shared"),
            SearchResult(frameId: vectorOnlyId, score: 0.8, content: "vector only"),
        ]

        let results = HybridSearch.fuse(
            textResults: textResults,
            vectorResults: vectorResults,
            alpha: 0.5,
            topK: 10
        )

        #expect(results[0].frameId == sharedId, "Document in both lists should rank highest")
    }

    @Test func topKLimit() {
        var textResults: [TextSearchResult] = []
        for _ in 0..<10 {
            textResults.append(TextSearchResult(frameId: UUID(), score: 1.0, snippet: "x"))
        }

        let results = HybridSearch.fuse(textResults: textResults, vectorResults: [], alpha: 0.0, topK: 3)
        #expect(results.count == 3)
    }
}
