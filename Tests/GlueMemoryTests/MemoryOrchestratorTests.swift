import Testing
import Foundation
@testable import GlueMemory

/// A deterministic embedding provider that generates hash-based vectors for testing.
/// Words that share common terms produce more similar embeddings.
struct StubEmbeddingProvider: EmbeddingProvider {
    let dimensions: Int = 64
    let normalize: Bool = true
    let identity = EmbeddingIdentity(provider: "stub", model: "hash", dimensions: 64)

    func embed(_ text: String) async throws -> [Float] {
        // Build a bag-of-words vector: hash each word to a dimension
        var vector = [Float](repeating: 0.0, count: dimensions)
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter })
        for word in words {
            let hash = abs(word.hashValue)
            let idx = hash % dimensions
            vector[idx] += 1.0
        }
        // L2 normalize
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            vector = vector.map { $0 / norm }
        }
        return vector
    }
}

@Suite("MemoryOrchestrator")
struct MemoryOrchestratorTests {
    func makeOrchestrator(
        enableText: Bool = true,
        enableVector: Bool = true
    ) -> MemoryOrchestrator {
        MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            embeddingProvider: enableVector ? StubEmbeddingProvider() : nil,
            config: OrchestratorConfig(
                enableTextSearch: enableText,
                enableVectorSearch: enableVector
            )
        )
    }

    @Test func rememberRecall() async throws {
        let orch = makeOrchestrator()
        let frame = try await orch.remember("Today I learned about Swift concurrency", metadata: ["source": "notes"])

        let recalled = try await orch.recall(id: frame.id)
        #expect(recalled != nil)
        #expect(recalled?.content == "Today I learned about Swift concurrency")
        #expect(recalled?.metadata["source"] == "notes")
    }

    @Test func forget() async throws {
        let orch = makeOrchestrator()
        let frame = try await orch.remember("Temporary note")
        try await orch.forget(id: frame.id)

        let recalled = try await orch.recall(id: frame.id)
        #expect(recalled == nil)
    }

    @Test func textSearch() async throws {
        let orch = makeOrchestrator(enableVector: false)

        try await orch.remember("PostgreSQL supports full-text search with tsvector")
        try await orch.remember("Redis is an in-memory data store")
        try await orch.remember("MySQL is a relational database management system")

        let response = try await orch.search(SearchRequest(query: "full-text search", mode: .textOnly, topK: 3))
        #expect(!response.results.isEmpty)
        #expect(response.results[0].content.contains("tsvector"))
    }

    @Test func vectorSearch() async throws {
        let orch = makeOrchestrator(enableText: false)

        try await orch.remember("Swift concurrency uses actors for safe mutable state")
        try await orch.remember("The weather today is sunny and warm")
        try await orch.remember("Actor isolation prevents data races in Swift")

        let response = try await orch.search(SearchRequest(query: "actors and concurrency in Swift", mode: .vectorOnly, topK: 3))
        #expect(!response.results.isEmpty)
    }

    @Test func hybridSearch() async throws {
        let orch = makeOrchestrator()

        try await orch.remember("Swift actors provide thread safety through isolation")
        try await orch.remember("Cooking pasta requires boiling water and salt")
        try await orch.remember("Thread safety in concurrent programming prevents data races")

        let response = try await orch.search(SearchRequest(query: "thread safety actors", mode: .hybrid(alpha: 0.5), topK: 3))
        #expect(!response.results.isEmpty)
    }

    @Test func listWithMetadata() async throws {
        let orch = makeOrchestrator()

        try await orch.remember("Note A", metadata: ["category": "work"])
        try await orch.remember("Note B", metadata: ["category": "personal"])
        try await orch.remember("Note C", metadata: ["category": "work"])

        let workNotes = try await orch.listFrames(metadata: ["category": "work"])
        #expect(workNotes.count == 2)
    }

    @Test func structuredMemory() async throws {
        let orch = makeOrchestrator()

        try await orch.addFact(entity: "swift", predicate: "version", value: .string("6.0"))
        try await orch.addFact(entity: "swift", predicate: "creator", value: .string("Apple"))
        try await orch.addFact(entity: "rust", predicate: "version", value: .string("1.75"))

        let swiftFacts = try await orch.facts(for: "swift")
        #expect(swiftFacts.count == 2)

        let version = try await orch.facts(for: "swift", predicate: "version")
        #expect(version.count == 1)
        #expect(version[0].value == .string("6.0"))

        let entities = try await orch.listEntities()
        #expect(entities.count == 2)
    }

    @Test func ragContext() async throws {
        let orch = makeOrchestrator(enableVector: false)

        for i in 0..<20 {
            try await orch.remember("Document number \(i) with some filler content about search and retrieval systems")
        }

        let context = try await orch.buildRAGContext(query: "search retrieval", mode: .textOnly, tokenBudget: 100)
        #expect(context.totalTokens <= 100)
        #expect(!context.items.isEmpty)
    }

    @Test func minScoreFilter() async throws {
        let orch = makeOrchestrator(enableVector: false)

        try await orch.remember("Exact match for database optimization techniques")
        try await orch.remember("The sky is blue and the grass is green")

        let response = try await orch.search(SearchRequest(
            query: "database optimization",
            mode: .textOnly,
            topK: 10,
            minScore: 0.01
        ))

        for result in response.results {
            #expect(result.score >= 0.01)
        }
    }
}
