import Testing
import Foundation
@testable import GlueMemory

@Suite("InMemoryTextIndex")
struct InMemoryTextIndexTests {
    @Test func basicSearch() async {
        let index = InMemoryTextIndex()

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        await index.index(frameId: id1, content: "The quick brown fox jumps over the lazy dog")
        await index.index(frameId: id2, content: "A fast red car drives on the highway")
        await index.index(frameId: id3, content: "The lazy cat sleeps on the brown mat")

        let results = await index.search(query: "brown lazy", topK: 3)

        // Both id1 and id3 contain "brown" and "lazy" — they should be top
        #expect(results.count >= 2)
        let topIds = results.prefix(2).map(\.frameId)
        #expect(topIds.contains(id1))
        #expect(topIds.contains(id3))
    }

    @Test func emptyQuery() async {
        let index = InMemoryTextIndex()
        await index.index(frameId: UUID(), content: "Some content here")
        let results = await index.search(query: "", topK: 5)
        #expect(results.isEmpty)
    }

    @Test func reindex() async {
        let index = InMemoryTextIndex()
        let id = UUID()

        await index.index(frameId: id, content: "original content about cats")
        var results = await index.search(query: "cats", topK: 1)
        #expect(results.count == 1)

        await index.index(frameId: id, content: "updated content about dogs")
        results = await index.search(query: "cats", topK: 1)
        #expect(results.isEmpty)

        results = await index.search(query: "dogs", topK: 1)
        #expect(results.count == 1)
        #expect(results[0].frameId == id)
    }

    @Test func removeDocument() async {
        let index = InMemoryTextIndex()
        let id = UUID()

        await index.index(frameId: id, content: "searchable content")
        await index.remove(frameId: id)

        let results = await index.search(query: "searchable", topK: 1)
        #expect(results.isEmpty)
    }

    @Test func bm25Ranking() async {
        let index = InMemoryTextIndex()
        let id1 = UUID()
        let id2 = UUID()

        // id1 has "machine learning" repeated, more relevant
        await index.index(frameId: id1, content: "Machine learning is a subset of artificial intelligence. Machine learning algorithms learn from data.")
        await index.index(frameId: id2, content: "The weather today is sunny with clear skies. Machine learning is interesting.")

        let results = await index.search(query: "machine learning", topK: 2)
        #expect(results.count == 2)
        #expect(results[0].frameId == id1, "Document with more term occurrences should rank higher")
    }
}
