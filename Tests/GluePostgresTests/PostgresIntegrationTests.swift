import Testing
import Foundation
@testable import GluePostgres
@testable import GlueMemory

/// Integration tests requiring a running PostgreSQL instance with pgvector.
/// Set GLUE_TEST_POSTGRES_URL environment variable to enable.
/// Example: GLUE_TEST_POSTGRES_URL=postgres://glue:glue@localhost:5432/glue_test

@Suite("PostgresIntegration", .serialized)
struct PostgresIntegrationTests {

    static let postgresURL = ProcessInfo.processInfo.environment["GLUE_TEST_POSTGRES_URL"]

    func withBackend(_ body: (PostgresStorageBackend) async throws -> Void) async throws {
        let url = Self.postgresURL!
        let config = try PostgresConfig.from(url: url)
        let backend = PostgresStorageBackend(config: config)
        try await backend.initialize()
        do {
            try await body(backend)
            try await backend.shutdown()
        } catch {
            try? await backend.shutdown()
            throw error
        }
    }

    @Test(.enabled(if: PostgresIntegrationTests.postgresURL != nil))
    func storeAndFetch() async throws {
        try await withBackend { backend in
            let frame = MemoryFrame(content: "Integration test content", metadata: ["env": "test"])
            try await backend.storeFrame(frame)

            let fetched = try await backend.fetchFrame(id: frame.id)
            #expect(fetched != nil)
            #expect(fetched?.content == "Integration test content")

            try await backend.deleteFrame(id: frame.id)
        }
    }

    @Test(.enabled(if: PostgresIntegrationTests.postgresURL != nil))
    func textSearch() async throws {
        try await withBackend { backend in
            let frame = MemoryFrame(content: "PostgreSQL full-text search integration test with tsvector")
            try await backend.storeFrame(frame)

            let results = try await backend.textSearch(query: "tsvector full-text", topK: 5)
            #expect(!results.isEmpty)

            try await backend.deleteFrame(id: frame.id)
        }
    }

    @Test(.enabled(if: PostgresIntegrationTests.postgresURL != nil))
    func structuredMemory() async throws {
        try await withBackend { backend in
            let fact = StructuredFact(
                entity: "test-user",
                predicate: "email",
                value: .string("test@example.com")
            )
            try await backend.storeFact(fact)

            let fetched = try await backend.fetchFacts(entity: "test-user")
            #expect(!fetched.isEmpty)
            #expect(fetched.first?.value.stringValue == "test@example.com")

            try await backend.deleteFact(id: fact.id)
        }
    }

    @Test(.enabled(if: PostgresIntegrationTests.postgresURL != nil))
    func listAndDeleteFrames() async throws {
        try await withBackend { backend in
            let frame1 = MemoryFrame(content: "Frame one", metadata: ["tag": "test-list"])
            let frame2 = MemoryFrame(content: "Frame two", metadata: ["tag": "test-list"])
            try await backend.storeFrame(frame1)
            try await backend.storeFrame(frame2)

            let listed = try await backend.listFrames(metadata: ["tag": "test-list"])
            #expect(listed.count >= 2)

            try await backend.deleteFrame(id: frame1.id)
            try await backend.deleteFrame(id: frame2.id)
        }
    }

    @Test(.enabled(if: PostgresIntegrationTests.postgresURL != nil))
    func updateFrame() async throws {
        try await withBackend { backend in
            let frame = MemoryFrame(content: "Original content")
            try await backend.storeFrame(frame)

            let updated = MemoryFrame(id: frame.id, content: "Updated content", createdAt: frame.createdAt)
            try await backend.updateFrame(updated)

            let fetched = try await backend.fetchFrame(id: frame.id)
            #expect(fetched?.content == "Updated content")

            try await backend.deleteFrame(id: frame.id)
        }
    }
}
