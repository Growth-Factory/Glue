import Foundation
import GlueMemory
import PostgresNIO
import Logging

/// PostgreSQL + pgvector implementation of `StorageBackend`.
///
/// Uses ``PostgresClient`` for connection pooling, making it safe for
/// concurrent use in Vapor and other server environments.
public actor PostgresStorageBackend: StorageBackend {
    private let client: PostgresClient
    private let config: PostgresConfig?
    private let logger: Logger
    private var runTask: Task<Void, Never>?

    /// Create a backend from configuration. The actor owns the pool lifecycle.
    public init(config: PostgresConfig, logger: Logger = Logger(label: "glue.postgres")) {
        self.config = config
        self.logger = logger
        self.client = PostgresClient(
            configuration: config.clientConfiguration,
            backgroundLogger: logger
        )
    }

    /// Create a backend from an externally-managed ``PostgresClient``.
    /// Use this when your application (e.g. Vapor) already owns a pool.
    /// The caller is responsible for calling `client.run()` and shutdown.
    public init(client: PostgresClient, logger: Logger = Logger(label: "glue.postgres")) {
        self.config = nil
        self.logger = logger
        self.client = client
    }

    // MARK: - Lifecycle

    public func initialize() async throws {
        // Only start the run loop if we own the client (config-based init)
        if config != nil {
            let client = self.client
            self.runTask = Task {
                await client.run()
            }
            // Give the run loop Task a chance to be scheduled by the executor.
            // Without this yield, the background Task may not have started yet
            // and the first query would trigger a PostgresClient warning.
            await Task.yield()
            try await waitForConnection(maxAttempts: 10, delayMs: 100)
        }

        try await client.withConnection { conn in
            try await PostgresMigrations.migrate(connection: conn)
        }
    }

    /// Retry a simple query until the connection pool is ready.
    private func waitForConnection(maxAttempts: Int, delayMs: UInt64) async throws {
        for attempt in 1...maxAttempts {
            do {
                _ = try await client.query("SELECT 1", logger: logger)
                logger.debug("PostgresClient connection ready (attempt \(attempt))")
                return
            } catch {
                if attempt == maxAttempts {
                    logger.error("PostgresClient failed to connect after \(maxAttempts) attempts: \(error)")
                    throw error
                }
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }
    }

    public func shutdown() async throws {
        runTask?.cancel()
        runTask = nil
    }

    // MARK: - Frame CRUD

    public func storeFrame(_ frame: MemoryFrame) async throws {
        let metadataJSON = try String(data: JSONEncoder().encode(frame.metadata), encoding: .utf8) ?? "{}"
        let tagsLiteral = pgArrayLiteral(frame.tags)

        if let embedding = frame.embedding {
            let vecLiteral = vectorLiteral(embedding)
            try await client.query(
                "INSERT INTO glue_frames (id, content, metadata, tags, embedding, created_at, updated_at) VALUES (\(frame.id), \(frame.content), \(metadataJSON)::jsonb, \(unescaped: "'\(tagsLiteral)'::text[]"), \(unescaped: "'\(vecLiteral)'::vector"), \(frame.createdAt), \(frame.updatedAt))",
                logger: logger
            )
        } else {
            try await client.query(
                "INSERT INTO glue_frames (id, content, metadata, tags, created_at, updated_at) VALUES (\(frame.id), \(frame.content), \(metadataJSON)::jsonb, \(unescaped: "'\(tagsLiteral)'::text[]"), \(frame.createdAt), \(frame.updatedAt))",
                logger: logger
            )
        }
    }

    public func storeFrames(_ frames: [MemoryFrame]) async throws {
        // Batch insert in chunks of 100
        for batch in frames.chunked(into: 100) {
            for frame in batch {
                try await storeFrame(frame)
            }
        }
    }

    public func fetchFrame(id: UUID) async throws -> MemoryFrame? {
        let rows = try await client.query(
            "SELECT id, content, metadata::text, tags::text, created_at, updated_at FROM glue_frames WHERE id = \(id)",
            logger: logger
        )
        for try await row in rows {
            return try decodeFrame(row)
        }
        return nil
    }

    public func updateFrame(_ frame: MemoryFrame) async throws {
        let metadataJSON = try String(data: JSONEncoder().encode(frame.metadata), encoding: .utf8) ?? "{}"
        let tagsLiteral = pgArrayLiteral(frame.tags)

        if let embedding = frame.embedding {
            let vecLiteral = vectorLiteral(embedding)
            try await client.query(
                "UPDATE glue_frames SET content = \(frame.content), metadata = \(metadataJSON)::jsonb, tags = \(unescaped: "'\(tagsLiteral)'::text[]"), embedding = \(unescaped: "'\(vecLiteral)'::vector"), updated_at = \(frame.updatedAt) WHERE id = \(frame.id)",
                logger: logger
            )
        } else {
            try await client.query(
                "UPDATE glue_frames SET content = \(frame.content), metadata = \(metadataJSON)::jsonb, tags = \(unescaped: "'\(tagsLiteral)'::text[]"), updated_at = \(frame.updatedAt) WHERE id = \(frame.id)",
                logger: logger
            )
        }
    }

    public func deleteFrame(id: UUID) async throws {
        try await client.query(
            "DELETE FROM glue_frames WHERE id = \(id)",
            logger: logger
        )
    }

    public func deleteFrames(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        // Delete using individual queries
        for id in ids {
            try await client.query(
                "DELETE FROM glue_frames WHERE id = \(id)",
                logger: logger
            )
        }
    }

    public func addTag(_ tag: String, to frameId: UUID) async throws {
        let escaped = tag.replacingOccurrences(of: "'", with: "''")
        try await client.query(
            PostgresQuery(unsafeSQL: "UPDATE glue_frames SET tags = array_append(tags, '\(escaped)'), updated_at = NOW() WHERE id = '\(frameId)' AND NOT ('\(escaped)' = ANY(tags))"),
            logger: logger
        )
    }

    public func addTags(_ tag: String, to frameIds: [UUID]) async throws {
        guard !frameIds.isEmpty else { return }
        let escaped = tag.replacingOccurrences(of: "'", with: "''")
        let idList = frameIds.map { "'\($0)'" }.joined(separator: ",")
        try await client.query(
            PostgresQuery(unsafeSQL: "UPDATE glue_frames SET tags = array_append(tags, '\(escaped)'), updated_at = NOW() WHERE id IN (\(idList)) AND NOT ('\(escaped)' = ANY(tags))"),
            logger: logger
        )
    }

    public func listFrames(metadata: [String: String]?) async throws -> [MemoryFrame] {
        if let metadata, !metadata.isEmpty {
            var sql = "SELECT id, content, metadata::text, tags::text, embedding::text, created_at, updated_at FROM glue_frames WHERE "
            var conditions: [String] = []
            for (key, value) in metadata {
                guard isValidMetadataKey(key) else {
                    throw GlueError.invalidConfiguration("Invalid metadata key: \(key)")
                }
                conditions.append("metadata->>'\(key)' = '\(value.replacingOccurrences(of: "'", with: "''"))'")
            }
            sql += conditions.joined(separator: " AND ")
            let rows = try await client.query(PostgresQuery(unsafeSQL: sql), logger: logger)
            var frames: [MemoryFrame] = []
            for try await row in rows {
                frames.append(try decodeFrameWithEmbedding(row))
            }
            return frames
        } else {
            let rows = try await client.query(
                "SELECT id, content, metadata::text, tags::text, embedding::text, created_at, updated_at FROM glue_frames",
                logger: logger
            )
            var frames: [MemoryFrame] = []
            for try await row in rows {
                frames.append(try decodeFrameWithEmbedding(row))
            }
            return frames
        }
    }

    // MARK: - Text Search

    public func textSearch(query: String, topK: Int) async throws -> [TextSearchResult] {
        let rows = try await client.query(
            "SELECT id, content, metadata::text, ts_rank(to_tsvector('english', content), plainto_tsquery('english', \(query))) AS rank FROM glue_frames WHERE to_tsvector('english', content) @@ plainto_tsquery('english', \(query)) ORDER BY rank DESC LIMIT \(topK)",
            logger: logger
        )

        var results: [TextSearchResult] = []
        for try await row in rows {
            let (id, content, metaJSON, rank) = try row.decode((UUID, String, String, Float).self, context: .default)
            let meta = Self.parseMetadata(metaJSON)
            results.append(TextSearchResult(frameId: id, score: rank, snippet: content, metadata: meta))
        }
        return results
    }

    public func textSearch(query: String, topK: Int, filters: [MetadataFilter]) async throws -> [TextSearchResult] {
        guard !filters.isEmpty else {
            return try await textSearch(query: query, topK: topK)
        }
        var sql = "SELECT id, content, metadata::text, ts_rank(to_tsvector('english', content), plainto_tsquery('english', '\(query.replacingOccurrences(of: "'", with: "''"))')) AS rank FROM glue_frames WHERE to_tsvector('english', content) @@ plainto_tsquery('english', '\(query.replacingOccurrences(of: "'", with: "''"))')"

        for filter in filters {
            sql += " AND " + filterToSQL(filter)
        }
        sql += " ORDER BY rank DESC LIMIT \(topK)"

        let rows = try await client.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var results: [TextSearchResult] = []
        for try await row in rows {
            let (id, content, metaJSON, rank) = try row.decode((UUID, String, String, Float).self, context: .default)
            let meta = Self.parseMetadata(metaJSON)
            results.append(TextSearchResult(frameId: id, score: rank, snippet: content, metadata: meta))
        }
        return results
    }

    // MARK: - Vector Search

    public func vectorSearch(embedding: [Float], topK: Int) async throws -> [SearchResult] {
        let vecStr = vectorLiteral(embedding)
        let rows = try await client.query(
            PostgresQuery(unsafeSQL: """
                SELECT id, content, metadata::text,
                       1 - (embedding <=> '\(vecStr)'::vector) AS similarity
                FROM glue_frames
                WHERE embedding IS NOT NULL
                ORDER BY embedding <=> '\(vecStr)'::vector
                LIMIT \(topK)
                """),
            logger: logger
        )

        var results: [SearchResult] = []
        for try await row in rows {
            let (id, content, metaJSON, similarity) = try row.decode((UUID, String, String, Float).self, context: .default)
            let meta = Self.parseMetadata(metaJSON)
            results.append(SearchResult(frameId: id, score: similarity, content: content, metadata: meta))
        }
        return results
    }

    public func vectorSearch(embedding: [Float], topK: Int, filters: [MetadataFilter]) async throws -> [SearchResult] {
        guard !filters.isEmpty else {
            return try await vectorSearch(embedding: embedding, topK: topK)
        }
        let vecStr = vectorLiteral(embedding)
        var sql = """
            SELECT id, content, metadata::text,
                   1 - (embedding <=> '\(vecStr)'::vector) AS similarity
            FROM glue_frames
            WHERE embedding IS NOT NULL
            """
        for filter in filters {
            sql += " AND " + filterToSQL(filter)
        }
        sql += " ORDER BY embedding <=> '\(vecStr)'::vector LIMIT \(topK)"

        let rows = try await client.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var results: [SearchResult] = []
        for try await row in rows {
            let (id, content, metaJSON, similarity) = try row.decode((UUID, String, String, Float).self, context: .default)
            let meta = Self.parseMetadata(metaJSON)
            results.append(SearchResult(frameId: id, score: similarity, content: content, metadata: meta))
        }
        return results
    }

    // MARK: - Structured Memory

    public func storeFact(_ fact: StructuredFact) async throws {
        let (valueType, valueData) = encodeFactValue(fact.value)

        let evidenceFrameId: UUID? = fact.evidence?.frameId
        let evidenceExcerpt: String? = fact.evidence?.excerpt
        let rangeStart: Date? = fact.timeRange?.start
        let rangeEnd: Date? = fact.timeRange?.end

        try await client.query(
            "INSERT INTO glue_facts (id, entity, predicate, value_type, value_data, evidence_frame_id, evidence_excerpt, time_range_start, time_range_end, created_at, updated_at) VALUES (\(fact.id), \(fact.entity.rawValue), \(fact.predicate.rawValue), \(valueType), \(valueData), \(evidenceFrameId), \(evidenceExcerpt), \(rangeStart), \(rangeEnd), \(fact.createdAt), \(fact.updatedAt))",
            logger: logger
        )
    }

    public func fetchFacts(entity: EntityKey) async throws -> [StructuredFact] {
        let rows = try await client.query(
            "SELECT id, entity, predicate, value_type, value_data, evidence_frame_id, evidence_excerpt, time_range_start, time_range_end, created_at, updated_at FROM glue_facts WHERE entity = \(entity.rawValue)",
            logger: logger
        )

        var facts: [StructuredFact] = []
        for try await row in rows {
            facts.append(try decodeFact(row))
        }
        return facts
    }

    public func fetchFacts(entity: EntityKey, predicate: PredicateKey) async throws -> [StructuredFact] {
        let rows = try await client.query(
            "SELECT id, entity, predicate, value_type, value_data, evidence_frame_id, evidence_excerpt, time_range_start, time_range_end, created_at, updated_at FROM glue_facts WHERE entity = \(entity.rawValue) AND predicate = \(predicate.rawValue)",
            logger: logger
        )

        var facts: [StructuredFact] = []
        for try await row in rows {
            facts.append(try decodeFact(row))
        }
        return facts
    }

    public func deleteFact(id: UUID) async throws {
        try await client.query(
            "DELETE FROM glue_facts WHERE id = \(id)",
            logger: logger
        )
    }

    public func updateFact(_ fact: StructuredFact) async throws {
        let (valueType, valueData) = encodeFactValue(fact.value)

        try await client.query(
            "UPDATE glue_facts SET value_type = \(valueType), value_data = \(valueData), updated_at = \(fact.updatedAt) WHERE id = \(fact.id)",
            logger: logger
        )
    }

    public func listEntities() async throws -> [EntityKey] {
        let rows = try await client.query(
            "SELECT DISTINCT entity FROM glue_facts ORDER BY entity",
            logger: logger
        )

        var entities: [EntityKey] = []
        for try await row in rows {
            let (name,) = try row.decode(String.self, context: .default)
            entities.append(EntityKey(name))
        }
        return entities
    }

    // MARK: - Private Helpers

    private static func parseMetadata(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func vectorLiteral(_ v: [Float]) -> String {
        "[" + v.map { String($0) }.joined(separator: ",") + "]"
    }

    /// Convert a Set<String> to a PostgreSQL text[] literal: {tag1,tag2}
    private func pgArrayLiteral(_ tags: Set<String>) -> String {
        let escaped = tags.sorted().map { $0.replacingOccurrences(of: "\"", with: "\\\"") }
        return "{" + escaped.map { "\"\($0)\"" }.joined(separator: ",") + "}"
    }

    /// Parse PostgreSQL text[] format: {tag1,tag2,"tag with spaces"} → Set<String>
    private func parsePgArray(_ text: String?) -> Set<String> {
        guard let text, text != "{}" else { return [] }
        // Strip outer braces
        let inner = text.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        guard !inner.isEmpty else { return [] }
        // Split on comma, strip quotes
        let items = inner.split(separator: ",").map { element in
            var s = String(element).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("\"") && s.hasSuffix("\"") {
                s = String(s.dropFirst().dropLast())
            }
            return s
        }
        return Set(items)
    }

    private func isValidMetadataKey(_ key: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return key.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func filterToSQL(_ filter: MetadataFilter) -> String {
        switch filter {
        case .equals(let key, let value):
            guard isValidMetadataKey(key) else { return "TRUE" }
            return "metadata->>'\(key)' = '\(value.replacingOccurrences(of: "'", with: "''"))'"
        case .contains(let key, let value):
            guard isValidMetadataKey(key) else { return "TRUE" }
            return "metadata->>'\(key)' LIKE '%' || '\(value.replacingOccurrences(of: "'", with: "''"))' || '%'"
        case .exists(let key):
            guard isValidMetadataKey(key) else { return "TRUE" }
            return "metadata ? '\(key)'"
        case .hasTag(let tag):
            return "'\(tag.replacingOccurrences(of: "'", with: "''"))' = ANY(tags)"
        }
    }

    private func encodeFactValue(_ value: FactValue) -> (type: String, data: String) {
        switch value {
        case .string(let v): return ("string", v)
        case .int(let v): return ("int", String(v))
        case .double(let v): return ("double", String(v))
        case .bool(let v): return ("bool", String(v))
        }
    }

    private func decodeFactValue(type: String, data: String) -> FactValue {
        switch type {
        case "int": return .int(Int(data) ?? 0)
        case "double": return .double(Double(data) ?? 0)
        case "bool": return .bool(data == "true")
        default: return .string(data)
        }
    }

    private func decodeFrame(_ row: PostgresRow) throws -> MemoryFrame {
        let (id, content, metadataJSON, tagsText, createdAt, updatedAt) = try row.decode(
            (UUID, String, String, String?, Date, Date).self, context: .default
        )

        let metadata = (try? JSONDecoder().decode([String: String].self, from: Data(metadataJSON.utf8))) ?? [:]

        return MemoryFrame(
            id: id,
            content: content,
            metadata: metadata,
            tags: parsePgArray(tagsText),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func decodeFrameWithEmbedding(_ row: PostgresRow) throws -> MemoryFrame {
        let (id, content, metadataJSON, tagsText, embeddingText, createdAt, updatedAt) = try row.decode(
            (UUID, String, String, String?, String?, Date, Date).self, context: .default
        )

        let metadata = (try? JSONDecoder().decode([String: String].self, from: Data(metadataJSON.utf8))) ?? [:]

        // Parse pgvector text format: "[0.1,0.2,0.3]"
        let embedding: [Float]? = embeddingText.flatMap { text in
            let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let floats = trimmed.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
            return floats.isEmpty ? nil : floats
        }

        return MemoryFrame(
            id: id,
            content: content,
            metadata: metadata,
            tags: parsePgArray(tagsText),
            embedding: embedding,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func decodeFact(_ row: PostgresRow) throws -> StructuredFact {
        let (id, entity, predicate, valueType, valueData,
             evidenceFrameId, evidenceExcerpt,
             rangeStart, rangeEnd, createdAt, updatedAt) = try row.decode(
            (UUID, String, String, String, String,
             UUID?, String?,
             Date?, Date?, Date, Date).self, context: .default
        )

        let evidence: StructuredEvidence? = evidenceFrameId.map {
            StructuredEvidence(frameId: $0, excerpt: evidenceExcerpt)
        }
        let timeRange: StructuredTimeRange?
        if rangeStart != nil || rangeEnd != nil {
            timeRange = StructuredTimeRange(start: rangeStart, end: rangeEnd)
        } else {
            timeRange = nil
        }

        return StructuredFact(
            id: id,
            entity: EntityKey(entity),
            predicate: PredicateKey(predicate),
            value: decodeFactValue(type: valueType, data: valueData),
            evidence: evidence,
            timeRange: timeRange,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
