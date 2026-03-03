/// Optional LLM-powered enhancements for search quality.
public protocol LLMEnhancer: Sendable {
    /// Expand a query into multiple related queries for better recall.
    func expandQuery(_ query: String) async throws -> [String]

    /// Generate a surrogate text summary for embedding.
    func generateSurrogate(_ text: String, maxTokens: Int) async throws -> String
}
