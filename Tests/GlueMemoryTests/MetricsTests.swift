import Testing
import Foundation
@testable import GlueMemory

/// A mock metrics collector that records calls.
actor MockMetricsCollector: MetricsCollector {
    var searchLatencies: [Duration] = []
    var ingestLatencies: [Duration] = []
    var searchResultCounts: [Int] = []
    var embeddingLatencies: [Duration] = []
    var ragBuildLatencies: [Duration] = []

    func recordSearchLatency(_ duration: Duration, mode: SearchMode) async {
        searchLatencies.append(duration)
    }

    func recordIngestLatency(_ duration: Duration) async {
        ingestLatencies.append(duration)
    }

    func recordSearchResultCount(_ count: Int, mode: SearchMode) async {
        searchResultCounts.append(count)
    }

    func recordEmbeddingLatency(_ duration: Duration) async {
        embeddingLatencies.append(duration)
    }

    func recordRAGBuildLatency(_ duration: Duration) async {
        ragBuildLatencies.append(duration)
    }
}

@Suite("Metrics")
struct MetricsTests {
    @Test func metricsRecorded() async throws {
        let collector = MockMetricsCollector()
        let orch = MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            metrics: collector,
            config: OrchestratorConfig(enableVectorSearch: false, defaultSearchMode: .textOnly)
        )

        try await orch.remember("test content about metrics")
        try await orch.search(SearchRequest(query: "metrics", mode: .textOnly))

        let ingestCount = await collector.ingestLatencies.count
        let searchCount = await collector.searchLatencies.count
        let resultCounts = await collector.searchResultCounts.count

        #expect(ingestCount == 1)
        #expect(searchCount == 1)
        #expect(resultCounts == 1)
    }

    @Test func ragMetrics() async throws {
        let collector = MockMetricsCollector()
        let orch = MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            metrics: collector,
            config: OrchestratorConfig(enableVectorSearch: false, defaultSearchMode: .textOnly)
        )

        try await orch.remember("content for RAG testing")
        _ = try await orch.buildRAGContext(query: "RAG", mode: .textOnly)

        let ragCount = await collector.ragBuildLatencies.count
        #expect(ragCount == 1)
    }

    @Test func nilCollectorNoCrash() async throws {
        let orch = MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            config: OrchestratorConfig(enableVectorSearch: false, defaultSearchMode: .textOnly)
        )

        try await orch.remember("no metrics collector")
        let response = try await orch.search(SearchRequest(query: "metrics", mode: .textOnly))
        #expect(response.results.count == 1)
    }
}
