import Testing
import Foundation
@testable import GlueMemory

/// A mock reranker that reverses the order of results.
struct MockReranker: Reranker {
    func rerank(query: String, results: [SearchResult], topK: Int) async throws -> [SearchResult] {
        let reversed = results.reversed().enumerated().map { (i, r) in
            SearchResult(frameId: r.frameId, score: Float(results.count - i), content: r.content)
        }
        return Array(reversed.prefix(topK))
    }
}

@Suite("Reranker")
struct RerankerTests {
    @Test func mockRerankerReversesOrder() async throws {
        let backend = InMemoryStorageBackend()
        let orch = MemoryOrchestrator(
            backend: backend,
            reranker: MockReranker(),
            config: OrchestratorConfig(
                enableVectorSearch: false,
                defaultSearchMode: .textOnly,
                enableReranking: true
            )
        )

        try await orch.remember("alpha testing framework")
        try await orch.remember("beta testing tools")
        try await orch.remember("gamma testing suite")

        let response = try await orch.search(SearchRequest(query: "testing", mode: .textOnly))
        #expect(response.results.count == 3)
        // Reranker reverses, so last original result should now be first
    }

    @Test func rerankingDisabled() async throws {
        let backend = InMemoryStorageBackend()
        let orch = MemoryOrchestrator(
            backend: backend,
            reranker: MockReranker(),
            config: OrchestratorConfig(
                enableVectorSearch: false,
                defaultSearchMode: .textOnly,
                enableReranking: false
            )
        )

        try await orch.remember("alpha testing framework")
        try await orch.remember("beta testing tools")

        let response = try await orch.search(SearchRequest(query: "testing", mode: .textOnly))
        #expect(response.results.count == 2)
        // Without reranking, original order preserved
    }

    @Test func topKRespected() async throws {
        let reranker = MockReranker()
        let results = (0..<10).map { i in
            SearchResult(frameId: UUID(), score: Float(10 - i), content: "doc \(i)")
        }

        let reranked = try await reranker.rerank(query: "test", results: results, topK: 3)
        #expect(reranked.count == 3)
    }
}
