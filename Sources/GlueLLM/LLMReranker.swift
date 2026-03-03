import GlueMemory
import AnyLanguageModel
import Foundation

/// A `Reranker` that uses an LLM to score document relevance.
/// Asks the model to rate each document 0-10 for relevance to the query,
/// then reorders results by those scores.
public struct LLMReranker: Reranker, Sendable {
    private let model: any LanguageModel

    public init(model: any LanguageModel) {
        self.model = model
    }

    public func rerank(query: String, results: [SearchResult], topK: Int) async throws -> [SearchResult] {
        guard !results.isEmpty else { return [] }

        let session = LanguageModelSession(model: model)

        // Build prompt with numbered documents
        var docList = ""
        for (i, result) in results.enumerated() {
            let snippet = String(result.content.prefix(500))
            docList += "[\(i)] \(snippet)\n\n"
        }

        let prompt = """
        Rate each document's relevance to the query on a scale of 0-10.
        Return ONLY a JSON array of numbers, one score per document, in order.
        Example: [8, 3, 10, 1]

        Query: \(query)

        Documents:
        \(docList)
        """

        let response = try await session.respond(to: prompt)
        let scores = parseScores(response.content, expectedCount: results.count)

        // Combine original results with new scores
        var scored = results.enumerated().map { (i, result) in
            SearchResult(frameId: result.frameId, score: scores[i], content: result.content)
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(topK))
    }

    /// Parse a JSON array of numeric scores from the LLM response.
    /// Falls back to uniform scores if parsing fails.
    private func parseScores(_ text: String, expectedCount: Int) -> [Float] {
        // Try to extract JSON array from response
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find array bounds
        guard let start = trimmed.firstIndex(of: "["),
              let end = trimmed.lastIndex(of: "]") else {
            return Array(repeating: Float(5.0), count: expectedCount)
        }

        let jsonStr = String(trimmed[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let parsed = try? JSONDecoder().decode([Double].self, from: data) else {
            return Array(repeating: Float(5.0), count: expectedCount)
        }

        // Ensure correct count
        if parsed.count == expectedCount {
            return parsed.map { Float($0) }
        }

        // Pad or truncate
        var scores = parsed.map { Float($0) }
        while scores.count < expectedCount {
            scores.append(5.0)
        }
        return Array(scores.prefix(expectedCount))
    }
}
