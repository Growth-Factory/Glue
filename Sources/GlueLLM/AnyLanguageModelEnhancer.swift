import GlueMemory
import AnyLanguageModel

/// LLMEnhancer implementation using AnyLanguageModel.
public struct AnyLanguageModelEnhancer: LLMEnhancer, Sendable {
    private let model: any LanguageModel

    public init(model: any LanguageModel) {
        self.model = model
    }

    public func expandQuery(_ query: String) async throws -> [String] {
        let session = LanguageModelSession(model: model)
        let prompt = """
        Given the following search query, generate 3 alternative phrasings that capture the same intent \
        but use different words. Return only the queries, one per line, with no numbering or extra text.

        Query: \(query)
        """

        let response = try await session.respond(to: prompt)
        let lines = response.content.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return [query] + lines
    }

    public func generateSurrogate(_ text: String, maxTokens: Int) async throws -> String {
        let session = LanguageModelSession(model: model)
        let prompt = """
        Summarize the following text in approximately \(maxTokens) tokens. \
        Focus on the key concepts and facts that would be useful for semantic search.

        Text: \(text)
        """

        let response = try await session.respond(to: prompt)
        return response.content
    }
}
