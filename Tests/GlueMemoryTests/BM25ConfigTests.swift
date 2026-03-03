import Testing
@testable import GlueMemory

@Suite("BM25Config")
struct BM25ConfigTests {
    @Test func defaultParams() {
        let config = BM25Config()
        #expect(config.k1 == 1.2)
        #expect(config.b == 0.75)
    }

    @Test func customParamsChangeRanking() async {
        // With default BM25 params
        let defaultIndex = InMemoryTextIndex()
        let id1 = UUID()
        let id2 = UUID()
        await defaultIndex.index(frameId: id1, content: "swift swift swift programming language")
        await defaultIndex.index(frameId: id2, content: "swift programming")
        let defaultResults = await defaultIndex.search(query: "swift", topK: 2)

        // With high k1 (higher term frequency saturation)
        let highK1Index = InMemoryTextIndex(config: BM25Config(k1: 3.0, b: 0.75))
        await highK1Index.index(frameId: id1, content: "swift swift swift programming language")
        await highK1Index.index(frameId: id2, content: "swift programming")
        let highK1Results = await highK1Index.search(query: "swift", topK: 2)

        // Both should return results but scores differ
        #expect(defaultResults.count == 2)
        #expect(highK1Results.count == 2)

        // High k1 should amplify the effect of repeated terms more
        let defaultRatio = defaultResults[0].score / defaultResults[1].score
        let highK1Ratio = highK1Results[0].score / highK1Results[1].score
        #expect(highK1Ratio > defaultRatio)
    }

    @Test func zeroLengthNormalization() async {
        // b=0 means no length normalization
        let index = InMemoryTextIndex(config: BM25Config(k1: 1.2, b: 0.0))
        let shortId = UUID()
        let longId = UUID()

        await index.index(frameId: shortId, content: "swift")
        await index.index(frameId: longId, content: "swift " + String(repeating: "filler ", count: 100))

        let results = await index.search(query: "swift", topK: 2)
        #expect(results.count == 2)
        // With b=0, document length shouldn't penalize the long doc as much
    }
}
