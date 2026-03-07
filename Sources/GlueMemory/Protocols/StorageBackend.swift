import Foundation

/// Central abstraction for pluggable storage backends.
/// Implementations must be `Sendable` (actors recommended).
public protocol StorageBackend: Sendable {

    // MARK: - Frame CRUD

    /// Store a new memory frame.
    func storeFrame(_ frame: MemoryFrame) async throws

    /// Store multiple frames at once.
    func storeFrames(_ frames: [MemoryFrame]) async throws

    /// Retrieve a frame by ID.
    func fetchFrame(id: UUID) async throws -> MemoryFrame?

    /// Update an existing frame.
    func updateFrame(_ frame: MemoryFrame) async throws

    /// Delete a frame by ID.
    func deleteFrame(id: UUID) async throws

    /// Delete multiple frames by ID.
    func deleteFrames(ids: [UUID]) async throws

    /// Add a tag to a frame without touching other fields.
    func addTag(_ tag: String, to frameId: UUID) async throws

    /// Add a tag to multiple frames.
    func addTags(_ tag: String, to frameIds: [UUID]) async throws

    /// List all frames, optionally filtered by metadata.
    func listFrames(metadata: [String: String]?) async throws -> [MemoryFrame]

    // MARK: - Text Search

    /// Full-text search returning scored results.
    func textSearch(query: String, topK: Int) async throws -> [TextSearchResult]

    /// Full-text search with metadata filters.
    func textSearch(query: String, topK: Int, filters: [MetadataFilter]) async throws -> [TextSearchResult]

    // MARK: - Vector Search

    /// Vector similarity search.
    func vectorSearch(embedding: [Float], topK: Int) async throws -> [SearchResult]

    /// Vector similarity search with metadata filters.
    func vectorSearch(embedding: [Float], topK: Int, filters: [MetadataFilter]) async throws -> [SearchResult]

    // MARK: - Structured Memory (Knowledge Graph)

    /// Store a structured fact.
    func storeFact(_ fact: StructuredFact) async throws

    /// Fetch all facts for an entity.
    func fetchFacts(entity: EntityKey) async throws -> [StructuredFact]

    /// Fetch facts matching entity + predicate.
    func fetchFacts(entity: EntityKey, predicate: PredicateKey) async throws -> [StructuredFact]

    /// Delete a fact by ID.
    func deleteFact(id: UUID) async throws

    /// Update an existing fact.
    func updateFact(_ fact: StructuredFact) async throws

    /// List all known entities.
    func listEntities() async throws -> [EntityKey]

    // MARK: - Lifecycle

    /// Perform any needed setup (migrations, index creation, etc.).
    func initialize() async throws

    /// Gracefully shut down (close connections, etc.).
    func shutdown() async throws
}

// MARK: - Default Implementations

extension StorageBackend {
    /// Default batch store: loops over individual storeFrame calls.
    public func storeFrames(_ frames: [MemoryFrame]) async throws {
        for frame in frames {
            try await storeFrame(frame)
        }
    }

    /// Default batch delete: loops over individual deleteFrame calls.
    public func deleteFrames(ids: [UUID]) async throws {
        for id in ids {
            try await deleteFrame(id: id)
        }
    }

    /// Default addTag: fetch, mutate, update (safe for in-memory, overridden for Postgres).
    public func addTag(_ tag: String, to frameId: UUID) async throws {
        guard var frame = try await fetchFrame(id: frameId) else { return }
        guard !frame.tags.contains(tag) else { return }
        frame.tags.insert(tag)
        frame.updatedAt = Date()
        try await updateFrame(frame)
    }

    /// Default addTags: loop over individual addTag calls.
    public func addTags(_ tag: String, to frameIds: [UUID]) async throws {
        for id in frameIds {
            try await addTag(tag, to: id)
        }
    }

    /// Default filtered text search: delegates to unfiltered then filters in memory.
    public func textSearch(query: String, topK: Int, filters: [MetadataFilter]) async throws -> [TextSearchResult] {
        let results = try await textSearch(query: query, topK: topK * 3)
        guard !filters.isEmpty else { return Array(results.prefix(topK)) }
        // Fetch frames to check metadata
        var filtered: [TextSearchResult] = []
        for result in results {
            guard filtered.count < topK else { break }
            if let frame = try await fetchFrame(id: result.frameId),
               matchesFilters(frame, filters: filters) {
                filtered.append(result)
            }
        }
        return filtered
    }

    /// Default filtered vector search: delegates to unfiltered then filters in memory.
    public func vectorSearch(embedding: [Float], topK: Int, filters: [MetadataFilter]) async throws -> [SearchResult] {
        let results = try await vectorSearch(embedding: embedding, topK: topK * 3)
        guard !filters.isEmpty else { return Array(results.prefix(topK)) }
        var filtered: [SearchResult] = []
        for result in results {
            guard filtered.count < topK else { break }
            if let frame = try await fetchFrame(id: result.frameId),
               matchesFilters(frame, filters: filters) {
                filtered.append(result)
            }
        }
        return filtered
    }
}

private func matchesFilters(_ frame: MemoryFrame, filters: [MetadataFilter]) -> Bool {
    filters.allSatisfy { filter in
        switch filter {
        case .equals(let key, let value):
            return frame.metadata[key] == value
        case .contains(let key, let value):
            return frame.metadata[key]?.contains(value) == true
        case .exists(let key):
            return frame.metadata[key] != nil
        case .hasTag(let tag):
            return frame.tags.contains(tag)
        }
    }
}
