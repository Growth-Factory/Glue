import Foundation

/// Central abstraction for pluggable storage backends.
/// Implementations must be `Sendable` (actors recommended).
public protocol StorageBackend: Sendable {

    // MARK: - Frame CRUD

    /// Store a new memory frame.
    func storeFrame(_ frame: MemoryFrame) async throws

    /// Retrieve a frame by ID.
    func fetchFrame(id: UUID) async throws -> MemoryFrame?

    /// Update an existing frame.
    func updateFrame(_ frame: MemoryFrame) async throws

    /// Delete a frame by ID.
    func deleteFrame(id: UUID) async throws

    /// List all frames, optionally filtered by metadata.
    func listFrames(metadata: [String: String]?) async throws -> [MemoryFrame]

    // MARK: - Text Search

    /// Full-text search returning scored results.
    func textSearch(query: String, topK: Int) async throws -> [TextSearchResult]

    // MARK: - Vector Search

    /// Vector similarity search.
    func vectorSearch(embedding: [Float], topK: Int) async throws -> [SearchResult]

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
