/// Protocol for post-retrieval reranking of search results.
/// Implementations score and reorder results for improved relevance.
public protocol Reranker: Sendable {
    func rerank(query: String, results: [SearchResult], topK: Int) async throws -> [SearchResult]
}
