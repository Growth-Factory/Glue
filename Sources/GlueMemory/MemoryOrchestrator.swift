import Foundation
import Logging

/// The main public API for Glue memory operations.
/// Coordinates storage, search, embeddings, and optional LLM enhancements.
public actor MemoryOrchestrator {
    private let backend: any StorageBackend
    private let embeddingProvider: (any EmbeddingProvider)?
    private let llmEnhancer: (any LLMEnhancer)?
    private let reranker: (any Reranker)?
    private let metrics: (any MetricsCollector)?
    private let config: OrchestratorConfig
    private let logger: Logger
    private let clock = ContinuousClock()

    public init(
        backend: any StorageBackend,
        embeddingProvider: (any EmbeddingProvider)? = nil,
        llmEnhancer: (any LLMEnhancer)? = nil,
        reranker: (any Reranker)? = nil,
        metrics: (any MetricsCollector)? = nil,
        config: OrchestratorConfig = OrchestratorConfig(),
        logger: Logger = Logger(label: "glue.memory")
    ) {
        self.backend = backend
        self.embeddingProvider = embeddingProvider
        self.llmEnhancer = llmEnhancer
        self.reranker = reranker
        self.metrics = metrics
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

    /// Store a piece of content in memory with optional metadata and tags.
    /// Returns the created `MemoryFrame`.
    ///
    /// Long content is automatically chunked using the configured `chunkingStrategy`.
    /// Each chunk is stored as a separate frame with `_parentId` and `_chunkIndex`
    /// metadata linking it back to the original. The first frame holds the full content.
    ///
    /// If `enableSurrogateGeneration` is on and an `LLMEnhancer` is provided,
    /// a summary is generated and appended to each chunk for better keyword matching.
    @discardableResult
    public func remember(
        _ content: String,
        metadata: [String: String] = [:],
        tags: Set<String> = []
    ) async throws -> MemoryFrame {
        let start = clock.now

        var meta = metadata

        // Deduplication check
        if config.deduplicationMode != .none {
            let hash = contentHash(content)
            meta["_contentHash"] = hash

            let existing = try await backend.listFrames(metadata: ["_contentHash": hash])
            if let existingFrame = existing.first {
                switch config.deduplicationMode {
                case .skip:
                    if let m = metrics { await m.recordIngestLatency(clock.now - start) }
                    return existingFrame
                case .replace:
                    var updated = existingFrame
                    updated.content = content
                    for (k, v) in meta { updated.metadata[k] = v }
                    updated.updatedAt = Date()
                    try await backend.updateFrame(updated)
                    if let m = metrics { await m.recordIngestLatency(clock.now - start) }
                    return updated
                case .none:
                    break
                }
            }
        }

        // Generate surrogate summary at ingest time
        var surrogate: String?
        if config.enableSurrogateGeneration, let enhancer = llmEnhancer {
            surrogate = try await enhancer.generateSurrogate(content, maxTokens: config.surrogateMaxTokens)
            meta["_surrogate"] = surrogate
            logger.debug("Generated surrogate for content (\(surrogate!.count) chars)")
        }

        // Chunk long content
        let chunks = TextChunker.chunk(content, strategy: config.chunkingStrategy, tokenCounter: config.tokenCounter)

        // Build embedding-enriched text (content + surrogate) for vector search,
        // but store only the original content to avoid polluting search results.
        let surrogateSuffix = surrogate.map { "\n\n" + $0 } ?? ""

        let result: MemoryFrame
        if chunks.count <= 1 {
            // Short content — store as a single frame
            result = try await storeOneFrame(
                content: content,
                embeddingContent: content + surrogateSuffix,
                metadata: meta,
                tags: tags
            )
        } else {
            // Long content — store full content as parent frame, then each chunk.
            // Batch-embed all texts (parent + chunks) in a single API call.
            let allEmbeddingTexts = [content + surrogateSuffix] + chunks.map { $0 + surrogateSuffix }

            var allEmbeddings: [[Float]?]
            if config.enableVectorSearch, let provider = embeddingProvider {
                let embStart = clock.now
                let vectors = try await provider.embedBatch(allEmbeddingTexts)
                allEmbeddings = vectors.map { Optional($0) }
                if let m = metrics { await m.recordEmbeddingLatency(clock.now - embStart) }
            } else {
                allEmbeddings = Array(repeating: nil, count: allEmbeddingTexts.count)
            }

            let parentFrame = try await storeOneFrame(
                content: content,
                metadata: meta,
                tags: tags,
                precomputedEmbedding: allEmbeddings[0]
            )

            for (i, chunk) in chunks.enumerated() {
                var chunkMeta = meta
                chunkMeta["_parentId"] = parentFrame.id.uuidString
                chunkMeta["_chunkIndex"] = String(i)
                try await storeOneFrame(
                    content: chunk,
                    metadata: chunkMeta,
                    tags: tags,
                    precomputedEmbedding: allEmbeddings[i + 1]
                )
            }

            logger.debug("Stored frame \(parentFrame.id) with \(chunks.count) chunks")
            result = parentFrame
        }

        if let m = metrics { await m.recordIngestLatency(clock.now - start) }
        return result
    }

    /// Store content with a pre-computed embedding vector.
    /// Use this when you've already batch-embedded outside the actor to avoid
    /// serialized per-item embedding calls.
    @discardableResult
    public func remember(
        _ content: String,
        precomputedEmbedding: [Float],
        metadata: [String: String] = [:],
        tags: Set<String> = []
    ) async throws -> MemoryFrame {
        let start = clock.now
        let result = try await storeOneFrame(
            content: content,
            metadata: metadata,
            tags: tags,
            precomputedEmbedding: precomputedEmbedding
        )
        if let m = metrics { await m.recordIngestLatency(clock.now - start) }
        return result
    }

    /// Batch-embed texts using the configured embedding provider.
    /// Call this outside the actor to compute embeddings concurrently,
    /// then pass results to `remember(_:precomputedEmbedding:metadata:tags:)`.
    /// Returns empty arrays if no embedding provider is configured.
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard let provider = embeddingProvider else { return [] }
        let start = clock.now
        let result = try await provider.embedBatch(texts)
        if let m = metrics { await m.recordEmbeddingLatency(clock.now - start) }
        return result
    }

    /// Store multiple items at once.
    /// Batch-embeds all content in a single API call, then stores each frame
    /// with its pre-computed embedding — much faster than sequential `remember()` calls.
    public func rememberBatch(
        _ items: [(content: String, metadata: [String: String])],
        tags: Set<String> = []
    ) async throws -> [MemoryFrame] {
        guard !items.isEmpty else { return [] }

        // Batch-embed all content in one API call (single network round-trip)
        let texts = items.map(\.content)
        var embeddings: [[Float]?]
        if config.enableVectorSearch, let provider = embeddingProvider {
            let embStart = clock.now
            let vectors = try await provider.embedBatch(texts)
            embeddings = vectors.map { Optional($0) }
            if let m = metrics { await m.recordEmbeddingLatency(clock.now - embStart) }
        } else {
            embeddings = Array(repeating: nil, count: items.count)
        }

        // Store each frame with its pre-computed embedding (no per-item network calls)
        var frames: [MemoryFrame] = []
        for (i, item) in items.enumerated() {
            let frame = try await storeOneFrame(
                content: item.content,
                metadata: item.metadata,
                tags: tags,
                precomputedEmbedding: embeddings[i]
            )
            frames.append(frame)
        }
        return frames
    }

    /// Store a single frame with optional embedding.
    /// - Parameters:
    ///   - content: The text stored in the frame (returned by search).
    ///   - embeddingContent: The text used to compute the embedding vector.
    ///     Pass enriched text (e.g. content + surrogate) to improve recall
    ///     without polluting the stored content.
    ///   - precomputedEmbedding: If provided, skip embedding computation and use this vector.
    @discardableResult
    private func storeOneFrame(
        content: String,
        embeddingContent: String? = nil,
        metadata: [String: String],
        tags: Set<String> = [],
        precomputedEmbedding: [Float]? = nil
    ) async throws -> MemoryFrame {
        var embedding: [Float]? = precomputedEmbedding
        if embedding == nil, config.enableVectorSearch, let provider = embeddingProvider {
            let embStart = clock.now
            embedding = try await provider.embed(embeddingContent ?? content)
            if let m = metrics { await m.recordEmbeddingLatency(clock.now - embStart) }
        }

        let frame = MemoryFrame(
            content: content,
            metadata: metadata,
            tags: tags,
            embedding: embedding
        )
        try await backend.storeFrame(frame)
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

    /// Duplicate an existing frame with new metadata, preserving its embedding.
    /// Use this when re-tagging cached content to avoid re-computing embeddings.
    @discardableResult
    public func duplicate(_ frame: MemoryFrame, metadata: [String: String]) async throws -> MemoryFrame {
        let newFrame = MemoryFrame(
            content: frame.content,
            metadata: metadata,
            embedding: frame.embedding
        )
        try await backend.storeFrame(newFrame)
        return newFrame
    }

    /// Add a tag to an existing frame. No-op if the frame already has the tag.
    public func addTag(_ tag: String, to frameId: UUID) async throws {
        try await backend.addTag(tag, to: frameId)
    }

    /// Add a tag to multiple frames at once.
    public func addTag(_ tag: String, to frameIds: [UUID]) async throws {
        try await backend.addTags(tag, to: frameIds)
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
        let searchStart = clock.now
        let mode = request.mode
        let topK = request.topK
        let query = request.query
        let filters = request.filters ?? []

        // Expand query if enabled
        var queries = [query]
        if config.enableQueryExpansion, let enhancer = llmEnhancer {
            queries = try await enhancer.expandQuery(query)
            logger.debug("Expanded query into \(queries.count) variants")
        }

        // Run search for each query variant and merge
        var bestByFrame: [UUID: SearchResult] = [:]
        for q in queries {
            let results = try await executeSearch(query: q, mode: mode, topK: topK, filters: filters)
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

        var merged = Array(bestByFrame.values)
            .sorted { $0.score > $1.score }

        // Apply reranking if enabled
        if config.enableReranking, let reranker = self.reranker {
            merged = try await reranker.rerank(query: query, results: merged, topK: topK)
        }

        merged = Array(merged.prefix(topK))

        let filtered: [SearchResult]
        if let minScore = request.minScore {
            filtered = merged.filter { $0.score >= minScore }
        } else {
            filtered = merged
        }

        if let m = metrics {
            await m.recordSearchLatency(clock.now - searchStart, mode: mode)
            await m.recordSearchResultCount(filtered.count, mode: mode)
        }

        return SearchResponse(results: filtered, query: query)
    }

    /// Execute a single search query for a given mode.
    private func executeSearch(
        query: String,
        mode: SearchMode,
        topK: Int,
        filters: [MetadataFilter]
    ) async throws -> [SearchResult] {
        switch mode {
        case .textOnly:
            guard config.enableTextSearch else {
                throw GlueError.invalidConfiguration("Text search is disabled")
            }
            let textResults: [TextSearchResult]
            if filters.isEmpty {
                textResults = try await backend.textSearch(query: query, topK: topK)
            } else {
                textResults = try await backend.textSearch(query: query, topK: topK, filters: filters)
            }
            return textResults.map { SearchResult(frameId: $0.frameId, score: $0.score, content: $0.snippet) }

        case .vectorOnly:
            guard config.enableVectorSearch else {
                throw GlueError.invalidConfiguration("Vector search is disabled")
            }
            guard let provider = embeddingProvider else {
                throw GlueError.embeddingProviderRequired
            }
            let queryEmbedding = try await provider.embed(query)
            if filters.isEmpty {
                return try await backend.vectorSearch(embedding: queryEmbedding, topK: topK)
            } else {
                return try await backend.vectorSearch(embedding: queryEmbedding, topK: topK, filters: filters)
            }

        case .hybrid(let alpha):
            var textResults: [TextSearchResult] = []
            var vectorResults: [SearchResult] = []

            if config.enableTextSearch {
                if filters.isEmpty {
                    textResults = try await backend.textSearch(query: query, topK: topK)
                } else {
                    textResults = try await backend.textSearch(query: query, topK: topK, filters: filters)
                }
            }
            if config.enableVectorSearch, let provider = embeddingProvider {
                let queryEmbedding = try await provider.embed(query)
                if filters.isEmpty {
                    vectorResults = try await backend.vectorSearch(embedding: queryEmbedding, topK: topK)
                } else {
                    vectorResults = try await backend.vectorSearch(embedding: queryEmbedding, topK: topK, filters: filters)
                }
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
        let ragStart = clock.now
        let request = SearchRequest(
            query: query,
            mode: mode ?? config.defaultSearchMode,
            topK: topK ?? config.defaultTopK
        )
        let response = try await search(request)
        let context = RAGContextBuilder.build(
            query: query,
            results: response.results,
            tokenBudget: tokenBudget ?? config.ragTokenBudget,
            chunkingStrategy: config.chunkingStrategy,
            tokenCounter: config.tokenCounter
        )
        if let m = metrics { await m.recordRAGBuildLatency(clock.now - ragStart) }
        return context
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

    // MARK: - Private Helpers

    /// Stable FNV-1a content hash for deduplication across process restarts.
    /// Uses FNV-1a (64-bit) which is deterministic, unlike Swift's Hasher.
    private func contentHash(_ content: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325 // FNV offset basis
        for byte in content.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3 // FNV prime
        }
        return String(format: "%016llx", hash)
    }
}
