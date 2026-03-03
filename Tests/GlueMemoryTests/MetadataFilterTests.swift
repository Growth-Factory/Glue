import Testing
import Foundation
@testable import GlueMemory

@Suite("MetadataFilter")
struct MetadataFilterTests {
    private func makeOrchestrator() -> MemoryOrchestrator {
        MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            config: OrchestratorConfig(enableVectorSearch: false, defaultSearchMode: .textOnly)
        )
    }

    @Test func equalsFilter() async throws {
        let orch = makeOrchestrator()
        try await orch.remember("Swift is a programming language", metadata: ["category": "tech"])
        try await orch.remember("Swift birds migrate south", metadata: ["category": "nature"])

        let request = SearchRequest(
            query: "swift",
            mode: .textOnly,
            filters: [.equals(key: "category", value: "tech")]
        )
        let response = try await orch.search(request)
        #expect(response.results.count == 1)
        #expect(response.results[0].content.contains("programming"))
    }

    @Test func containsFilter() async throws {
        let orch = makeOrchestrator()
        try await orch.remember("Database systems overview", metadata: ["tags": "database,sql,postgres"])
        try await orch.remember("Frontend development guide", metadata: ["tags": "react,javascript"])

        let request = SearchRequest(
            query: "systems",
            mode: .textOnly,
            filters: [.contains(key: "tags", value: "sql")]
        )
        let response = try await orch.search(request)
        #expect(response.results.count == 1)
    }

    @Test func existsFilter() async throws {
        let orch = makeOrchestrator()
        try await orch.remember("Important document", metadata: ["priority": "high"])
        try await orch.remember("Regular document", metadata: [:])

        let request = SearchRequest(
            query: "document",
            mode: .textOnly,
            filters: [.exists(key: "priority")]
        )
        let response = try await orch.search(request)
        #expect(response.results.count == 1)
        #expect(response.results[0].content.contains("Important"))
    }

    @Test func combinedFilters() async throws {
        let orch = makeOrchestrator()
        try await orch.remember("Swift iOS development", metadata: ["category": "tech", "platform": "ios"])
        try await orch.remember("Swift backend development", metadata: ["category": "tech", "platform": "linux"])
        try await orch.remember("Swift bird watching", metadata: ["category": "nature"])

        let request = SearchRequest(
            query: "swift",
            mode: .textOnly,
            filters: [
                .equals(key: "category", value: "tech"),
                .equals(key: "platform", value: "ios"),
            ]
        )
        let response = try await orch.search(request)
        #expect(response.results.count == 1)
        #expect(response.results[0].content.contains("iOS"))
    }

    @Test func emptyFilters() async throws {
        let orch = makeOrchestrator()
        try await orch.remember("First document about testing", metadata: [:])
        try await orch.remember("Second document about testing", metadata: [:])

        let request = SearchRequest(query: "testing", mode: .textOnly, filters: [])
        let response = try await orch.search(request)
        #expect(response.results.count == 2)
    }
}
