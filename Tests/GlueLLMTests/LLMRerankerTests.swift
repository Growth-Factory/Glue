import Testing
import Foundation
import AnyLanguageModel
@testable import GlueLLM
@testable import GlueMemory

/// Mock language model that returns known scores for reranking.
struct MockRerankerModel: LanguageModel {
    let responseText: String

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let rawContent = GeneratedContent(responseText)
        let content = try Content(rawContent)
        return LanguageModelSession.Response(
            content: content,
            rawContent: rawContent,
            transcriptEntries: []
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let rawContent = GeneratedContent(responseText)
        let content = try! Content(rawContent)
        return LanguageModelSession.ResponseStream(content: content, rawContent: rawContent)
    }
}

@Suite("LLMReranker")
struct LLMRerankerTests {
    @Test func reranksWithKnownScores() async throws {
        let model = MockRerankerModel(responseText: "[2.0, 9.0, 5.0]")
        let reranker = LLMReranker(model: model)

        let results = [
            SearchResult(frameId: UUID(), score: 1.0, content: "low relevance doc"),
            SearchResult(frameId: UUID(), score: 0.9, content: "high relevance doc"),
            SearchResult(frameId: UUID(), score: 0.8, content: "medium relevance doc"),
        ]

        let reranked = try await reranker.rerank(query: "test", results: results, topK: 3)
        #expect(reranked.count == 3)
        // Second doc got score 9.0, should be first
        #expect(reranked[0].score == 9.0)
        #expect(reranked[0].content == "high relevance doc")
    }

    @Test func fallbackOnBadJSON() async throws {
        let model = MockRerankerModel(responseText: "I can't rate these documents properly.")
        let reranker = LLMReranker(model: model)

        let results = [
            SearchResult(frameId: UUID(), score: 1.0, content: "doc A"),
            SearchResult(frameId: UUID(), score: 0.5, content: "doc B"),
        ]

        let reranked = try await reranker.rerank(query: "test", results: results, topK: 2)
        #expect(reranked.count == 2)
        // Fallback gives uniform 5.0 scores
        #expect(reranked[0].score == 5.0)
    }

    @Test func topKRespected() async throws {
        let model = MockRerankerModel(responseText: "[8.0, 3.0, 10.0, 1.0, 7.0]")
        let reranker = LLMReranker(model: model)

        let results = (0..<5).map { i in
            SearchResult(frameId: UUID(), score: Float(5 - i), content: "doc \(i)")
        }

        let reranked = try await reranker.rerank(query: "test", results: results, topK: 2)
        #expect(reranked.count == 2)
        #expect(reranked[0].score == 10.0)
    }

    @Test func emptyResults() async throws {
        let model = MockRerankerModel(responseText: "[]")
        let reranker = LLMReranker(model: model)

        let reranked = try await reranker.rerank(query: "test", results: [], topK: 5)
        #expect(reranked.isEmpty)
    }
}
