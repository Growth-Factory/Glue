import Testing
import Foundation
@testable import GlueMemory

@Suite("Deduplication")
struct DeduplicationTests {
    @Test func noneDuplicates() async throws {
        let orch = MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            config: OrchestratorConfig(enableVectorSearch: false, deduplicationMode: .none)
        )

        let frame1 = try await orch.remember("duplicate content")
        let frame2 = try await orch.remember("duplicate content")

        #expect(frame1.id != frame2.id)
        let all = try await orch.listFrames()
        #expect(all.count == 2)
    }

    @Test func skipReturnsExisting() async throws {
        let orch = MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            config: OrchestratorConfig(enableVectorSearch: false, deduplicationMode: .skip)
        )

        let frame1 = try await orch.remember("duplicate content", metadata: ["v": "1"])
        let frame2 = try await orch.remember("duplicate content", metadata: ["v": "2"])

        #expect(frame1.id == frame2.id)
        let all = try await orch.listFrames()
        #expect(all.count == 1)
        // Original metadata preserved
        #expect(all[0].metadata["v"] == "1")
    }

    @Test func replaceUpdatesExisting() async throws {
        let orch = MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            config: OrchestratorConfig(enableVectorSearch: false, deduplicationMode: .replace)
        )

        let frame1 = try await orch.remember("duplicate content", metadata: ["v": "1"])
        let frame2 = try await orch.remember("duplicate content", metadata: ["v": "2"])

        #expect(frame1.id == frame2.id)
        let all = try await orch.listFrames()
        #expect(all.count == 1)
        // Metadata updated
        #expect(all[0].metadata["v"] == "2")
    }

    @Test func differentContentNotDeduplicated() async throws {
        let orch = MemoryOrchestrator(
            backend: InMemoryStorageBackend(),
            config: OrchestratorConfig(enableVectorSearch: false, deduplicationMode: .skip)
        )

        try await orch.remember("content A")
        try await orch.remember("content B")

        let all = try await orch.listFrames()
        #expect(all.count == 2)
    }
}
