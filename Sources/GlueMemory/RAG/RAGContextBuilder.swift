/// Builds RAG context from search results within a token budget.
public enum RAGContextBuilder: Sendable {
    /// Assemble a RAG context from search results, respecting the token budget.
    ///
    /// - Parameters:
    ///   - query: The original query.
    ///   - results: Search results sorted by relevance.
    ///   - tokenBudget: Maximum total tokens for the context.
    /// - Returns: A `RAGContext` containing the top results that fit within the budget.
    public static func build(
        query: String,
        results: [SearchResult],
        tokenBudget: Int
    ) -> RAGContext {
        var items: [RAGContextItem] = []
        var totalTokens = 0

        for result in results {
            let tokenCount = TokenCounter.count(result.content)
            if totalTokens + tokenCount > tokenBudget {
                // Try to include a truncated version if we have room
                let remainingBudget = tokenBudget - totalTokens
                if remainingBudget > 20 {
                    // Rough truncation by words
                    let words = result.content.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                    let wordsToTake = Int(Double(remainingBudget) / 1.33)
                    if wordsToTake > 0 {
                        let truncated = words.prefix(wordsToTake).joined(separator: " ")
                        let truncTokens = TokenCounter.count(truncated)
                        items.append(RAGContextItem(content: truncated, score: result.score, tokenCount: truncTokens))
                        totalTokens += truncTokens
                    }
                }
                break
            }
            items.append(RAGContextItem(content: result.content, score: result.score, tokenCount: tokenCount))
            totalTokens += tokenCount
        }

        return RAGContext(query: query, items: items, totalTokens: totalTokens)
    }
}
