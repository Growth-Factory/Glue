import Foundation
import Logging

/// The main public API for Glue memory operations.
/// Coordinates storage, search, embeddings, and optional LLM enhancements.
public actor MemoryOrchestrator {
    private let backend: any StorageBackend
    private let embeddingProvider: (any EmbeddingProvider)?
    private let llmEnhancer: (any LLMEnhancer)?
    private let config: OrchestratorConfig
    private let logger: Logger

    public init(
        backend: any StorageBackend,
        embeddingProvider: (any EmbeddingProvider)? = nil,
        llmEnhancer: (any LLMEnhancer)? = nil,
        config: OrchestratorConfig = OrchestratorConfig(),
        logger: Logger = Logger(label: "glue.memory")
    ) {
        self.backend = backend
        self.embeddingProvider = embeddingProvider
        self.llmEnhancer = llmEnhancer
        self.config = config
        self.logger = logger
    }

    /// Initialize the backend (run migrations, etc.).
    public func initialize() async throws {
        try await backend.initialize()
    }

    /// Shut down the backend.
    public func shutdown() async throws {
        try await backend.shutdown()
    }

    // MARK: - Remember / Recall

    /// Store a piece of content in memory with optional metadata.
    /// Returns the created `MemoryFrame`.
    ///
    /// If `enableSurrogateGeneration` is on and an `LLMEnhancer` is provided,
    /// a summary/keywords are generated and stored in `metadata["_surrogate"]`.
    /// The surrogate is appended to the content for indexing so that BM25 and
    /// vector search can match on the generated terms too.
    @discardableResult
    public func remember(
        _ content: String,
        metadata: [String: String] = [:]
    ) async throws -> MemoryFrame {
        var meta = metadata
        var storedContent = content

        // Generate surrogate summary at ingest time
        if config.enableSurrogateGeneration, let enhancer = llmEnhancer {
            let surrogate = try await enhancer.generateSurrogate(content, maxTokens: config.surrogateMaxTokens)
            meta["_surrogate"] = surrogate
            storedContent = content + "\n\n" + surrogate
            logger.debug("Generated surrogate for content (\(surrogate.count) chars)")
        }

        var embedding: [Float]?
        if config.enableVectorSearch, let provider = embeddingProvider {
            embedding = try await provider.embed(storedContent)
        }

        let frame = MemoryFrame(
            content: storedContent,
            metadata: meta,
            embedding: embedding
        )
        try await backend.storeFrame(frame)
        logger.debug("Stored frame \(frame.id)")
        return frame
    }

    /// Recall a specific memory frame by ID.
    public func recall(id: UUID) async throws -> MemoryFrame? {
        try await backend.fetchFrame(id: id)
    }

    /// List all frames, optionally filtered by metadata.
    public func listFrames(metadata: [String: String]? = nil) async throws -> [MemoryFrame] {
        try await backend.listFrames(metadata: metadata)
    }

    /// Delete a frame by ID.
    public func forget(id: UUID) async throws {
        try await backend.deleteFrame(id: id)
        logger.debug("Deleted frame \(id)")
    }

    // MARK: - Search

    /// Search memory using the specified mode (or the default from config).
    ///
    /// If `enableQueryExpansion` is on and an `LLMEnhancer` is provided,
    /// the query is expanded into multiple variants. Each variant is searched
    /// independently and results are merged, keeping the best score per frame.
    public func search(_ request: SearchRequest) async throws -> SearchResponse {
        let mode = request.mode
        let topK = request.topK
        let query = request.query

        // Expand query if enabled
        var queries = [query]
        if config.enableQueryExpansion, let enhancer = llmEnhancer {
            queries = try await enhancer.expandQuery(query)
            logger.debug("Expanded query into \(queries.count) variants")
        }

        // Run search for each query variant and merge
        var bestByFrame: [UUID: SearchResult] = [:]
        for q in queries {
            let results = try await executeSearch(query: q, mode: mode, topK: topK)
            for r in results {
                if let existing = bestByFrame[r.frameId] {
                    if r.score > existing.score {
                        bestByFrame[r.frameId] = r
                    }
                } else {
                    bestByFrame[r.frameId] = r
                }
            }
        }

        let merged = Array(bestByFrame.values)
            .sorted { $0.score > $1.score }
            .prefix(topK)

        let filtered: [SearchResult]
        if let minScore = request.minScore {
            filtered = Array(merged).filter { $0.score >= minScore }
        } else {
            filtered = Array(merged)
        }

        return SearchResponse(results: filtered, query: query)
    }

    /// Execute a single search query for a given mode.
    private func executeSearch(query: String, mode: SearchMode, topK: Int) async throws -> [SearchResult] {
        switch mode {
        case .textOnly:
            guard config.enableTextSearch else {
                throw GlueError.invalidConfiguration("Text search is disabled")
            }
            let textResults = try await backend.textSearch(query: query, topK: topK)
            return textResults.map { SearchResult(frameId: $0.frameId, score: $0.score, content: $0.snippet) }

        case .vectorOnly:
            guard config.enableVectorSearch else {
                throw GlueError.invalidConfiguration("Vector search is disabled")
            }
            guard let provider = embeddingProvider else {
                throw GlueError.embeddingProviderRequired
            }
            let queryEmbedding = try await provider.embed(query)
            return try await backend.vectorSearch(embedding: queryEmbedding, topK: topK)

        case .hybrid(let alpha):
            var textResults: [TextSearchResult] = []
            var vectorResults: [SearchResult] = []

            if config.enableTextSearch {
                textResults = try await backend.textSearch(query: query, topK: topK)
            }
            if config.enableVectorSearch, let provider = embeddingProvider {
                let queryEmbedding = try await provider.embed(query)
                vectorResults = try await backend.vectorSearch(embedding: queryEmbedding, topK: topK)
            }

            return HybridSearch.fuse(
                textResults: textResults,
                vectorResults: vectorResults,
                alpha: alpha,
                topK: topK
            )
        }
    }

    // MARK: - RAG Context

    /// Build a token-budgeted RAG context from search results.
    public func buildRAGContext(
        query: String,
        mode: SearchMode? = nil,
        topK: Int? = nil,
        tokenBudget: Int? = nil
    ) async throws -> RAGContext {
        let request = SearchRequest(
            query: query,
            mode: mode ?? config.defaultSearchMode,
            topK: topK ?? config.defaultTopK
        )
        let response = try await search(request)
        return RAGContextBuilder.build(
            query: query,
            results: response.results,
            tokenBudget: tokenBudget ?? config.ragTokenBudget
        )
    }

    // MARK: - Structured Memory (Knowledge Graph)

    /// Store a structured fact.
    @discardableResult
    public func addFact(
        entity: EntityKey,
        predicate: PredicateKey,
        value: FactValue,
        evidence: StructuredEvidence? = nil,
        timeRange: StructuredTimeRange? = nil
    ) async throws -> StructuredFact {
        let fact = StructuredFact(
            entity: entity,
            predicate: predicate,
            value: value,
            evidence: evidence,
            timeRange: timeRange
        )
        try await backend.storeFact(fact)
        logger.debug("Stored fact \(fact.id) for entity \(entity.rawValue)")
        return fact
    }

    /// Fetch all facts for an entity.
    public func facts(for entity: EntityKey) async throws -> [StructuredFact] {
        try await backend.fetchFacts(entity: entity)
    }

    /// Fetch facts for an entity + predicate.
    public func facts(for entity: EntityKey, predicate: PredicateKey) async throws -> [StructuredFact] {
        try await backend.fetchFacts(entity: entity, predicate: predicate)
    }

    /// Delete a fact by ID.
    public func deleteFact(id: UUID) async throws {
        try await backend.deleteFact(id: id)
    }

    /// List all known entities.
    public func listEntities() async throws -> [EntityKey] {
        try await backend.listEntities()
    }
}
