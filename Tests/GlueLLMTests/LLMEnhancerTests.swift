import Testing
import Foundation
@testable import GlueLLM
@testable import GlueMemory
import AnyLanguageModel

/// A mock language model conforming to AnyLanguageModel's LanguageModel protocol.
struct MockLanguageModel: LanguageModel {
    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let promptText = prompt.description

        let responseText: String
        if promptText.contains("alternative phrasings") {
            responseText = """
            rephrased query one
            rephrased query two
            rephrased query three
            """
        } else if promptText.contains("Summarize") {
            responseText = "A concise summary of the input text covering key concepts."
        } else {
            responseText = "Mock response"
        }

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
        let rawContent = GeneratedContent("Mock stream response")
        let content: Content
        do {
            content = try Content(rawContent)
        } catch {
            fatalError("Failed to create Content from GeneratedContent: \(error)")
        }
        return LanguageModelSession.ResponseStream(content: content, rawContent: rawContent)
    }
}

@Suite("LLMEnhancer")
struct LLMEnhancerTests {
    @Test func queryExpansion() async throws {
        let enhancer = AnyLanguageModelEnhancer(model: MockLanguageModel())

        let queries = try await enhancer.expandQuery("machine learning algorithms")
        #expect(queries.count >= 2, "Should return original + expanded queries")
        #expect(queries[0] == "machine learning algorithms", "First should be original query")
    }

    @Test func surrogateGeneration() async throws {
        let enhancer = AnyLanguageModelEnhancer(model: MockLanguageModel())

        let summary = try await enhancer.generateSurrogate("A very long document about many topics...", maxTokens: 100)
        #expect(!summary.isEmpty)
        #expect(summary.contains("summary"))
    }
}
