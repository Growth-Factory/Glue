import Foundation
import GlueMemory
import PostgresNIO
import Logging

/// PostgreSQL + pgvector implementation of `StorageBackend`.
public actor PostgresStorageBackend: StorageBackend {
    private let config: PostgresConfig
    private let logger: Logger
    private var connection: PostgresConnection?

    public init(config: PostgresConfig, logger: Logger = Logger(label: "glue.postgres")) {
        self.config = config
        self.logger = logger
    }

    // MARK: - Lifecycle

    public func initialize() async throws {
        let conn = try await PostgresConnection.connect(
            configuration: config.connectionConfig,
            id: 1,
            logger: logger
        )
        self.connection = conn
        try await PostgresMigrations.migrate(connection: conn)
    }

    public func shutdown() async throws {
        try await connection?.close()
        connection = nil
    }

    // MARK: - Frame CRUD

    public func storeFrame(_ frame: MemoryFrame) async throws {
        let conn = try requireConnection()
        let metadataJSON = try String(data: JSONEncoder().encode(frame.metadata), encoding: .utf8) ?? "{}"
        let embeddingStr = frame.embedding.map { vectorLiteral($0) }

        if let embStr = embeddingStr {
            try await conn.query(
                PostgresQuery(unsafeSQL: """
                    INSERT INTO glue_frames (id, content, metadata, embedding, created_at, updated_at)
                    VALUES ('\(frame.id.uuidString)', \(escapeSQLString(frame.content)), '\(metadataJSON)'::jsonb, '\(embStr)'::vector, \(timestampLiteral(frame.createdAt)), \(timestampLiteral(frame.updatedAt)))
                    """),
                logger: logger
            )
        } else {
            try await conn.query(
                PostgresQuery(unsafeSQL: """
                    INSERT INTO glue_frames (id, content, metadata, created_at, updated_at)
                    VALUES ('\(frame.id.uuidString)', \(escapeSQLString(frame.content)), '\(metadataJSON)'::jsonb, \(timestampLiteral(frame.createdAt)), \(timestampLiteral(frame.updatedAt)))
                    """),
                logger: logger
            )
        }
    }

    public func fetchFrame(id: UUID) async throws -> MemoryFrame? {
        let conn = try requireConnection()
        let rows = try await conn.query(
            PostgresQuery(unsafeSQL: """
                SELECT id, content, metadata::text, created_at, updated_at
                FROM glue_frames WHERE id = '\(id.uuidString)'
                """),
            logger: logger
        )
        for try await row in rows {
            return try decodeFrame(row)
        }
        return nil
    }

    public func updateFrame(_ frame: MemoryFrame) async throws {
        let conn = try requireConnection()
        let metadataJSON = try String(data: JSONEncoder().encode(frame.metadata), encoding: .utf8) ?? "{}"

        if let embedding = frame.embedding {
            try await conn.query(
                PostgresQuery(unsafeSQL: """
                    UPDATE glue_frames SET content = \(escapeSQLString(frame.content)),
                    metadata = '\(metadataJSON)'::jsonb,
                    embedding = '\(vectorLiteral(embedding))'::vector,
                    updated_at = \(timestampLiteral(frame.updatedAt))
                    WHERE id = '\(frame.id.uuidString)'
                    """),
                logger: logger
            )
        } else {
            try await conn.query(
                PostgresQuery(unsafeSQL: """
                    UPDATE glue_frames SET content = \(escapeSQLString(frame.content)),
                    metadata = '\(metadataJSON)'::jsonb,
                    updated_at = \(timestampLiteral(frame.updatedAt))
                    WHERE id = '\(frame.id.uuidString)'
                    """),
                logger: logger
            )
        }
    }

    public func deleteFrame(id: UUID) async throws {
        let conn = try requireConnection()
        try await conn.query(
            PostgresQuery(unsafeSQL: "DELETE FROM glue_frames WHERE id = '\(id.uuidString)'"),
            logger: logger
        )
    }

    public func listFrames(metadata: [String: String]?) async throws -> [MemoryFrame] {
        let conn = try requireConnection()
        var sql = "SELECT id, content, metadata::text, created_at, updated_at FROM glue_frames"

        if let metadata, !metadata.isEmpty {
            let conditions = metadata.map { (key, value) in
                "metadata->>'\(key)' = \(escapeSQLString(value))"
            }
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }

        let rows = try await conn.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var frames: [MemoryFrame] = []
        for try await row in rows {
            frames.append(try decodeFrame(row))
        }
        return frames
    }

    // MARK: - Text Search

    public func textSearch(query: String, topK: Int) async throws -> [TextSearchResult] {
        let conn = try requireConnection()
        let rows = try await conn.query(
            PostgresQuery(unsafeSQL: """
                SELECT id, content,
                       ts_rank(to_tsvector('english', content), plainto_tsquery('english', \(escapeSQLString(query)))) AS rank
                FROM glue_frames
                WHERE to_tsvector('english', content) @@ plainto_tsquery('english', \(escapeSQLString(query)))
                ORDER BY rank DESC
                LIMIT \(topK)
                """),
            logger: logger
        )

        var results: [TextSearchResult] = []
        for try await row in rows {
            let (id, content, rank) = try row.decode((UUID, String, Float).self, context: .default)
            results.append(TextSearchResult(frameId: id, score: rank, snippet: content))
        }
        return results
    }

    // MARK: - Vector Search

    public func vectorSearch(embedding: [Float], topK: Int) async throws -> [SearchResult] {
        let conn = try requireConnection()
        let vecStr = vectorLiteral(embedding)
        let rows = try await conn.query(
            PostgresQuery(unsafeSQL: """
                SELECT id, content,
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
            let (id, content, similarity) = try row.decode((UUID, String, Float).self, context: .default)
            results.append(SearchResult(frameId: id, score: similarity, content: content))
        }
        return results
    }

    // MARK: - Structured Memory

    public func storeFact(_ fact: StructuredFact) async throws {
        let conn = try requireConnection()
        let (valueType, valueData) = encodeFactValue(fact.value)
        let evidenceFrameId = fact.evidence?.frameId.uuidString ?? "NULL"
        let evidenceExcerpt = fact.evidence?.excerpt.map { escapeSQLString($0) } ?? "NULL"
        let rangeStart = fact.timeRange?.start.map { timestampLiteral($0) } ?? "NULL"
        let rangeEnd = fact.timeRange?.end.map { timestampLiteral($0) } ?? "NULL"

        let evidenceFrameSQL = fact.evidence?.frameId != nil ? "'\(evidenceFrameId)'" : "NULL"

        try await conn.query(
            PostgresQuery(unsafeSQL: """
                INSERT INTO glue_facts (id, entity, predicate, value_type, value_data,
                    evidence_frame_id, evidence_excerpt, time_range_start, time_range_end,
                    created_at, updated_at)
                VALUES ('\(fact.id.uuidString)', \(escapeSQLString(fact.entity.rawValue)),
                    \(escapeSQLString(fact.predicate.rawValue)),
                    \(escapeSQLString(valueType)), \(escapeSQLString(valueData)),
                    \(evidenceFrameSQL), \(evidenceExcerpt),
                    \(rangeStart), \(rangeEnd),
                    \(timestampLiteral(fact.createdAt)), \(timestampLiteral(fact.updatedAt)))
                """),
            logger: logger
        )
    }

    public func fetchFacts(entity: EntityKey) async throws -> [StructuredFact] {
        let conn = try requireConnection()
        let rows = try await conn.query(
            PostgresQuery(unsafeSQL: """
                SELECT id, entity, predicate, value_type, value_data,
                       evidence_frame_id, evidence_excerpt,
                       time_range_start, time_range_end, created_at, updated_at
                FROM glue_facts WHERE entity = \(escapeSQLString(entity.rawValue))
                """),
            logger: logger
        )

        var facts: [StructuredFact] = []
        for try await row in rows {
            facts.append(try decodeFact(row))
        }
        return facts
    }

    public func fetchFacts(entity: EntityKey, predicate: PredicateKey) async throws -> [StructuredFact] {
        let conn = try requireConnection()
        let rows = try await conn.query(
            PostgresQuery(unsafeSQL: """
                SELECT id, entity, predicate, value_type, value_data,
                       evidence_frame_id, evidence_excerpt,
                       time_range_start, time_range_end, created_at, updated_at
                FROM glue_facts
                WHERE entity = \(escapeSQLString(entity.rawValue))
                  AND predicate = \(escapeSQLString(predicate.rawValue))
                """),
            logger: logger
        )

        var facts: [StructuredFact] = []
        for try await row in rows {
            facts.append(try decodeFact(row))
        }
        return facts
    }

    public func deleteFact(id: UUID) async throws {
        let conn = try requireConnection()
        try await conn.query(
            PostgresQuery(unsafeSQL: "DELETE FROM glue_facts WHERE id = '\(id.uuidString)'"),
            logger: logger
        )
    }

    public func updateFact(_ fact: StructuredFact) async throws {
        let conn = try requireConnection()
        let (valueType, valueData) = encodeFactValue(fact.value)

        try await conn.query(
            PostgresQuery(unsafeSQL: """
                UPDATE glue_facts SET
                    value_type = \(escapeSQLString(valueType)),
                    value_data = \(escapeSQLString(valueData)),
                    updated_at = \(timestampLiteral(fact.updatedAt))
                WHERE id = '\(fact.id.uuidString)'
                """),
            logger: logger
        )
    }

    public func listEntities() async throws -> [EntityKey] {
        let conn = try requireConnection()
        let rows = try await conn.query(
            PostgresQuery(unsafeSQL: "SELECT DISTINCT entity FROM glue_facts ORDER BY entity"),
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

    private func requireConnection() throws -> PostgresConnection {
        guard let conn = connection else {
            throw GlueError.backendError("PostgreSQL connection not initialized. Call initialize() first.")
        }
        return conn
    }

    private func vectorLiteral(_ v: [Float]) -> String {
        "[" + v.map { String($0) }.joined(separator: ",") + "]"
    }

    private func escapeSQLString(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func timestampLiteral(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "'\(formatter.string(from: date))'::timestamptz"
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
        let (id, content, metadataJSON, createdAt, updatedAt) = try row.decode(
            (UUID, String, String, Date, Date).self, context: .default
        )

        let metadata = (try? JSONDecoder().decode([String: String].self, from: Data(metadataJSON.utf8))) ?? [:]

        return MemoryFrame(
            id: id,
            content: content,
            metadata: metadata,
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
