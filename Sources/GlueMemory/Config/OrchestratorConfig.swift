/// Configuration for the MemoryOrchestrator.
public struct OrchestratorConfig: Sendable {
    /// Enable full-text search capabilities.
    public var enableTextSearch: Bool

    /// Enable vector similarity search capabilities.
    public var enableVectorSearch: Bool

    /// Default search mode when not specified.
    public var defaultSearchMode: SearchMode

    /// Default number of results to return.
    public var defaultTopK: Int

    /// Default chunking strategy for long texts.
    public var chunkingStrategy: ChunkingStrategy

    /// Maximum token budget for RAG context assembly.
    public var ragTokenBudget: Int

    /// Generate a surrogate summary at ingest time (requires LLMEnhancer).
    /// The surrogate is appended to the indexed content to improve keyword recall.
    public var enableSurrogateGeneration: Bool

    /// Max tokens for surrogate text generation.
    public var surrogateMaxTokens: Int

    /// Expand queries at search time into multiple variants (requires LLMEnhancer).
    /// Each variant is searched independently and results are merged by best score.
    public var enableQueryExpansion: Bool

    /// BM25 text search parameters.
    public var bm25Config: BM25Config

    /// Custom token counter. When nil, the built-in `TokenCounter` is used.
    public var tokenCounter: (any TokenCounting)?

    /// Enable post-retrieval reranking of search results.
    public var enableReranking: Bool

    /// Deduplication mode for content ingestion.
    public var deduplicationMode: DeduplicationMode

    public init(
        enableTextSearch: Bool = true,
        enableVectorSearch: Bool = true,
        defaultSearchMode: SearchMode = .hybrid,
        defaultTopK: Int = 10,
        chunkingStrategy: ChunkingStrategy = .default,
        ragTokenBudget: Int = 4096,
        enableSurrogateGeneration: Bool = false,
        surrogateMaxTokens: Int = 128,
        enableQueryExpansion: Bool = false,
        bm25Config: BM25Config = BM25Config(),
        tokenCounter: (any TokenCounting)? = nil,
        enableReranking: Bool = false,
        deduplicationMode: DeduplicationMode = .none
    ) {
        self.enableTextSearch = enableTextSearch
        self.enableVectorSearch = enableVectorSearch
        self.defaultSearchMode = defaultSearchMode
        self.defaultTopK = defaultTopK
        self.chunkingStrategy = chunkingStrategy
        self.ragTokenBudget = ragTokenBudget
        self.enableSurrogateGeneration = enableSurrogateGeneration
        self.surrogateMaxTokens = surrogateMaxTokens
        self.enableQueryExpansion = enableQueryExpansion
        self.bm25Config = bm25Config
        self.tokenCounter = tokenCounter
        self.enableReranking = enableReranking
        self.deduplicationMode = deduplicationMode
    }
}
