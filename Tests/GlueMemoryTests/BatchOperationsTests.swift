import Testing
import Foundation
@testable import GlueMemory

@Suite("BatchOperations")
struct BatchOperationsTests {
    @Test func batchStore() async throws {
        let backend = InMemoryStorageBackend()
        let frames = (0..<5).map { i in
            MemoryFrame(content: "Document \(i)", metadata: ["index": "\(i)"])
        }
        try await backend.storeFrames(frames)

        let stored = try await backend.listFrames(metadata: nil)
        #expect(stored.count == 5)
    }

    @Test func batchDelete() async throws {
        let backend = InMemoryStorageBackend()
        let frames = (0..<5).map { i in
            MemoryFrame(content: "Document \(i)")
        }
        try await backend.storeFrames(frames)

        let idsToDelete = frames.prefix(3).map(\.id)
        try await backend.deleteFrames(ids: Array(idsToDelete))

        let remaining = try await backend.listFrames(metadata: nil)
        #expect(remaining.count == 2)
    }

    @Test func emptyBatch() async throws {
        let backend = InMemoryStorageBackend()
        try await backend.storeFrames([])
        let stored = try await backend.listFrames(metadata: nil)
        #expect(stored.isEmpty)

        try await backend.deleteFrames(ids: [])
        // Should not throw
    }

    @Test func rememberBatch() async throws {
        let orch = MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            config: OrchestratorConfig(enableVectorSearch: false)
        )

        let items: [(content: String, metadata: [String: String])] = [
            ("First item about testing", ["type": "test"]),
            ("Second item about building", ["type": "build"]),
            ("Third item about deploying", ["type": "deploy"]),
        ]

        let frames = try await orch.rememberBatch(items)
        #expect(frames.count == 3)

        let all = try await orch.listFrames()
        #expect(all.count == 3)
    }
}
