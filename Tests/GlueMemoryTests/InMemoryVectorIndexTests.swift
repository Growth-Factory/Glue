import Testing
import Foundation
@testable import GlueMemory

@Suite("InMemoryVectorIndex")
struct InMemoryVectorIndexTests {
    @Test func identicalVectors() async {
        let index = InMemoryVectorIndex()
        let id = UUID()
        let vec: [Float] = [1.0, 0.0, 0.0]

        await index.index(frameId: id, embedding: vec)
        let results = await index.search(query: vec, topK: 1)

        #expect(results.count == 1)
        #expect(results[0].0 == id)
        #expect(abs(results[0].1 - 1.0) < 0.001)
    }

    @Test func orthogonalVectors() async {
        let index = InMemoryVectorIndex()
        let id = UUID()

        await index.index(frameId: id, embedding: [1.0, 0.0, 0.0])
        let results = await index.search(query: [0.0, 1.0, 0.0], topK: 1)

        #expect(results.isEmpty, "Orthogonal vectors should have 0 similarity and be filtered out")
    }

    @Test func ranking() async {
        let index = InMemoryVectorIndex()
        let idClose = UUID()
        let idFar = UUID()

        // Close to query direction
        await index.index(frameId: idClose, embedding: [0.9, 0.1, 0.0])
        // Far from query direction
        await index.index(frameId: idFar, embedding: [0.1, 0.9, 0.0])

        let results = await index.search(query: [1.0, 0.0, 0.0], topK: 2)
        #expect(results.count == 2)
        #expect(results[0].0 == idClose, "Closer vector should rank first")
    }

    @Test func topKLimit() async {
        let index = InMemoryVectorIndex()

        for _ in 0..<10 {
            await index.index(frameId: UUID(), embedding: [Float.random(in: 0...1), Float.random(in: 0...1)])
        }

        let results = await index.search(query: [0.5, 0.5], topK: 3)
        #expect(results.count <= 3)
    }

    @Test func removeVector() async {
        let index = InMemoryVectorIndex()
        let id = UUID()

        await index.index(frameId: id, embedding: [1.0, 0.0])
        await index.remove(frameId: id)

        let results = await index.search(query: [1.0, 0.0], topK: 1)
        #expect(results.isEmpty)
    }
}
