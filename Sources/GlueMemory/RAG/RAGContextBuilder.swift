import Foundation

/// Builds RAG context from search results within a token budget.
public enum RAGContextBuilder: Sendable {
    /// Assemble a RAG context from search results, respecting the token budget.
    /// Documents that fit whole are included as-is. Documents that exceed the
    /// remaining budget are chunked via `TextChunker` and individual chunks are
    /// included until the budget is exhausted. Content is never truncated
    /// mid-sentence — chunking preserves natural boundaries with overlap.
    ///
    /// Results that don't fit are tracked in `RAGContext.overflow` so callers
    /// always know what was excluded.
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
        var includedFrameIds: Set<UUID> = []
        var droppedResults: [RAGContext.DroppedResult] = []

        for result in results {
            let remaining = tokenBudget - totalTokens

            if remaining <= 0 {
                // Budget exhausted — collect as dropped
                let tokenCount = counter.count(result.content)
                droppedResults.append(RAGContext.DroppedResult(
                    frameId: result.frameId,
                    score: result.score,
                    estimatedTokens: tokenCount
                ))
                continue
            }

            let tokenCount = counter.count(result.content)
            if tokenCount <= remaining {
                // Fits whole — include as-is
                items.append(RAGContextItem(
                    content: result.content,
                    score: result.score,
                    tokenCount: tokenCount,
                    sourceFrameId: result.frameId
                ))
                totalTokens += tokenCount
                includedFrameIds.insert(result.frameId)
            } else {
                // Doesn't fit whole — chunk and include what fits
                let chunks = TextChunker.chunk(result.content, strategy: chunkingStrategy, tokenCounter: tokenCounter)
                let totalChunks = chunks.count
                var anyChunkIncluded = false

                for (index, chunk) in chunks.enumerated() {
                    let chunkTokens = counter.count(chunk)
                    if totalTokens + chunkTokens <= tokenBudget {
                        items.append(RAGContextItem(
                            content: chunk,
                            score: result.score,
                            tokenCount: chunkTokens,
                            sourceFrameId: result.frameId,
                            isChunk: true,
                            chunkIndex: index,
                            totalChunksInSource: totalChunks
                        ))
                        totalTokens += chunkTokens
                        anyChunkIncluded = true
                    }
                    // Don't break — continue to count remaining for overflow
                }

                if anyChunkIncluded {
                    includedFrameIds.insert(result.frameId)
                }

                // If no chunks fit at all, record as fully dropped
                if !anyChunkIncluded {
                    droppedResults.append(RAGContext.DroppedResult(
                        frameId: result.frameId,
                        score: result.score,
                        estimatedTokens: tokenCount
                    ))
                }
            }
        }

        let overflow = RAGContext.Overflow(
            totalResultsProvided: results.count,
            resultsIncluded: includedFrameIds.count,
            resultsDropped: droppedResults.count,
            droppedResults: droppedResults
        )

        return RAGContext(query: query, items: items, totalTokens: totalTokens, overflow: overflow)
    }
}
