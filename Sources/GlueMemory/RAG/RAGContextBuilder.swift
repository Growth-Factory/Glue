/// Builds RAG context from search results within a token budget.
public enum RAGContextBuilder: Sendable {
    /// Assemble a RAG context from search results, respecting the token budget.
    /// Documents that fit whole are included as-is. Documents that exceed the
    /// remaining budget are chunked via `TextChunker` and individual chunks are
    /// included until the budget is exhausted. Content is never truncated
    /// mid-sentence — chunking preserves natural boundaries with overlap.
    public static func build(
        query: String,
        results: [SearchResult],
        tokenBudget: Int,
        chunkingStrategy: ChunkingStrategy = .default,
        tokenCounter: (any TokenCounting)? = nil
    ) -> RAGContext {
        let counter = tokenCounter ?? TokenCounter()
        var items: [RAGContextItem] = []
        var totalTokens = 0

        for result in results {
            let remaining = tokenBudget - totalTokens
            if remaining <= 0 { break }

            let tokenCount = counter.count(result.content)
            if tokenCount <= remaining {
                // Fits whole — include as-is
                items.append(RAGContextItem(content: result.content, score: result.score, tokenCount: tokenCount))
                totalTokens += tokenCount
            } else {
                // Doesn't fit whole — chunk and include what fits
                let chunks = TextChunker.chunk(result.content, strategy: chunkingStrategy, tokenCounter: tokenCounter)
                for chunk in chunks {
                    let chunkTokens = counter.count(chunk)
                    if totalTokens + chunkTokens <= tokenBudget {
                        items.append(RAGContextItem(content: chunk, score: result.score, tokenCount: chunkTokens))
                        totalTokens += chunkTokens
                    } else {
                        break
                    }
                }
            }
        }

        return RAGContext(query: query, items: items, totalTokens: totalTokens)
    }
}
