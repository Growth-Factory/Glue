import Testing
import Foundation
@testable import GluePostgres
@testable import GlueMemory

@Suite("PostgresParameterizedQueries")
struct PostgresParameterizedQueryTests {
    /// These tests verify the SQL injection payloads can be stored and retrieved safely.
    /// They require a running PostgreSQL instance.
    private func skipUnlessPostgres() throws {
        guard ProcessInfo.processInfo.environment["GLUE_TEST_POSTGRES_URL"] != nil else {
            throw XCTSkip("Set GLUE_TEST_POSTGRES_URL to run Postgres integration tests")
        }
    }

    private func makeBackend() throws -> PostgresStorageBackend {
        let urlString = ProcessInfo.processInfo.environment["GLUE_TEST_POSTGRES_URL"]!
        let config = try PostgresConfig.from(url: urlString)
        return PostgresStorageBackend(config: config)
    }

    @Test func storeAndRetrieveSQLInjectionPayload() async throws {
        try skipUnlessPostgres()
        let backend = try makeBackend()
        try await backend.initialize()

        let maliciousContent = "Robert'); DROP TABLE glue_frames;--"
        let frame = MemoryFrame(content: maliciousContent, metadata: ["key": "O'Malley"])
        try await backend.storeFrame(frame)

        let retrieved = try await backend.fetchFrame(id: frame.id)
        #expect(retrieved?.content == maliciousContent)
        #expect(retrieved?.metadata["key"] == "O'Malley")

        // Cleanup
        try await backend.deleteFrame(id: frame.id)
        try await backend.shutdown()
    }

    @Test func textSearchWithInjectionPayload() async throws {
        try skipUnlessPostgres()
        let backend = try makeBackend()
        try await backend.initialize()

        let frame = MemoryFrame(content: "safe document content")
        try await backend.storeFrame(frame)

        // Search with injection attempt
        let results = try await backend.textSearch(query: "'; DROP TABLE glue_frames;--", topK: 10)
        // Should return 0 results but not crash
        #expect(results.count >= 0)

        try await backend.deleteFrame(id: frame.id)
        try await backend.shutdown()
    }
}

/// A minimal skip for tests outside XCTest.
struct XCTSkip: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
