import Foundation

/// Full in-memory `StorageBackend` implementation for testing and lightweight use.
public actor InMemoryStorageBackend: StorageBackend {
    private var frames: [UUID: MemoryFrame] = [:]
    private var facts: [UUID: StructuredFact] = [:]
    private let textIndex: InMemoryTextIndex
    private let vectorIndex = InMemoryVectorIndex()

    public init(bm25Config: BM25Config = BM25Config()) {
        self.textIndex = InMemoryTextIndex(config: bm25Config)
    }

    // MARK: - Frame CRUD

    public func storeFrame(_ frame: MemoryFrame) async throws {
        frames[frame.id] = frame
        await textIndex.index(frameId: frame.id, content: frame.content)
        if let embedding = frame.embedding {
            await vectorIndex.index(frameId: frame.id, embedding: embedding)
        }
    }

    public func fetchFrame(id: UUID) async throws -> MemoryFrame? {
        frames[id]
    }

    public func updateFrame(_ frame: MemoryFrame) async throws {
        guard frames[frame.id] != nil else {
            throw GlueError.frameNotFound(frame.id)
        }
        frames[frame.id] = frame
        await textIndex.index(frameId: frame.id, content: frame.content)
        if let embedding = frame.embedding {
            await vectorIndex.index(frameId: frame.id, embedding: embedding)
        }
    }

    public func deleteFrame(id: UUID) async throws {
        frames.removeValue(forKey: id)
        await textIndex.remove(frameId: id)
        await vectorIndex.remove(frameId: id)
    }

    public func listFrames(metadata: [String: String]?) async throws -> [MemoryFrame] {
        let allFrames = Array(frames.values)
        guard let metadata else { return allFrames }

        return allFrames.filter { frame in
            metadata.allSatisfy { (key, value) in
                frame.metadata[key] == value
            }
        }
    }

    // MARK: - Text Search

    public func textSearch(query: String, topK: Int) async throws -> [TextSearchResult] {
        await textIndex.search(query: query, topK: topK)
    }

    public func textSearch(query: String, topK: Int, filters: [MetadataFilter]) async throws -> [TextSearchResult] {
        guard !filters.isEmpty else {
            return try await textSearch(query: query, topK: topK)
        }
        let results = await textIndex.search(query: query, topK: topK * 3)
        var filtered: [TextSearchResult] = []
        for result in results {
            guard filtered.count < topK else { break }
            if let frame = frames[result.frameId], matchesFilters(frame.metadata, filters: filters) {
                filtered.append(result)
            }
        }
        return filtered
    }

    // MARK: - Vector Search

    public func vectorSearch(embedding: [Float], topK: Int) async throws -> [SearchResult] {
        let results = await vectorIndex.search(query: embedding, topK: topK)
        return results.compactMap { (id, score) in
            guard let frame = frames[id] else { return nil }
            return SearchResult(frameId: id, score: score, content: frame.content)
        }
    }

    public func vectorSearch(embedding: [Float], topK: Int, filters: [MetadataFilter]) async throws -> [SearchResult] {
        guard !filters.isEmpty else {
            return try await vectorSearch(embedding: embedding, topK: topK)
        }
        let results = await vectorIndex.search(query: embedding, topK: topK * 3)
        var filtered: [SearchResult] = []
        for (id, score) in results {
            guard filtered.count < topK else { break }
            if let frame = frames[id], matchesFilters(frame.metadata, filters: filters) {
                filtered.append(SearchResult(frameId: id, score: score, content: frame.content))
            }
        }
        return filtered
    }

    // MARK: - Structured Memory

    public func storeFact(_ fact: StructuredFact) async throws {
        facts[fact.id] = fact
    }

    public func fetchFacts(entity: EntityKey) async throws -> [StructuredFact] {
        facts.values.filter { $0.entity == entity }
    }

    public func fetchFacts(entity: EntityKey, predicate: PredicateKey) async throws -> [StructuredFact] {
        facts.values.filter { $0.entity == entity && $0.predicate == predicate }
    }

    public func deleteFact(id: UUID) async throws {
        facts.removeValue(forKey: id)
    }

    public func updateFact(_ fact: StructuredFact) async throws {
        guard facts[fact.id] != nil else {
            throw GlueError.factNotFound(fact.id)
        }
        facts[fact.id] = fact
    }

    public func listEntities() async throws -> [EntityKey] {
        Array(Set(facts.values.map(\.entity)))
    }

    // MARK: - Lifecycle

    public func initialize() async throws {}
    public func shutdown() async throws {}

    // MARK: - Private

    private func matchesFilters(_ metadata: [String: String], filters: [MetadataFilter]) -> Bool {
        filters.allSatisfy { filter in
            switch filter {
            case .equals(let key, let value):
                return metadata[key] == value
            case .contains(let key, let value):
                return metadata[key]?.contains(value) == true
            case .exists(let key):
                return metadata[key] != nil
            }
        }
    }
}
