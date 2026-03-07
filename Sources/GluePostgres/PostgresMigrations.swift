import PostgresNIO
import GlueMemory
import Logging

/// DDL migrations for Glue's PostgreSQL schema.
public enum PostgresMigrations: Sendable {
    /// Run all migrations using a pooled ``PostgresClient``.
    public static func migrate(client: PostgresClient) async throws {
        try await client.withConnection { conn in
            try await migrate(connection: conn)
        }
    }

    /// Create a vector index using a pooled ``PostgresClient``.
    public static func createVectorIndex(
        client: PostgresClient,
        dimensions: Int,
        indexType: VectorIndexType = .default
    ) async throws {
        try await client.withConnection { conn in
            try await createVectorIndex(connection: conn, dimensions: dimensions, indexType: indexType)
        }
    }

    /// Run all migrations on the given connection.
    public static func migrate(connection: PostgresConnection) async throws {
        // Enable pgvector extension
        try await connection.query(
            "CREATE EXTENSION IF NOT EXISTS vector",
            logger: .init(label: "glue.migrations")
        )

        // Memory frames table
        try await connection.query("""
            CREATE TABLE IF NOT EXISTS glue_frames (
                id UUID PRIMARY KEY,
                content TEXT NOT NULL,
                metadata JSONB NOT NULL DEFAULT '{}',
                embedding vector,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            """,
            logger: .init(label: "glue.migrations")
        )

        // Full-text search index
        try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_glue_frames_fts
            ON glue_frames USING gin(to_tsvector('english', content))
            """,
            logger: .init(label: "glue.migrations")
        )

        // Content hash index for deduplication
        try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_glue_frames_content_hash
            ON glue_frames ((metadata->>'_contentHash'))
            """,
            logger: .init(label: "glue.migrations")
        )

        // Tags array column (multi-tag support)
        try await connection.query("""
            ALTER TABLE glue_frames ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}'
            """,
            logger: .init(label: "glue.migrations")
        )

        // GIN index for fast tag lookups
        try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_glue_frames_tags
            ON glue_frames USING gin(tags)
            """,
            logger: .init(label: "glue.migrations")
        )

        // Structured facts table
        try await connection.query("""
            CREATE TABLE IF NOT EXISTS glue_facts (
                id UUID PRIMARY KEY,
                entity TEXT NOT NULL,
                predicate TEXT NOT NULL,
                value_type TEXT NOT NULL,
                value_data TEXT NOT NULL,
                evidence_frame_id UUID REFERENCES glue_frames(id) ON DELETE SET NULL,
                evidence_excerpt TEXT,
                time_range_start TIMESTAMPTZ,
                time_range_end TIMESTAMPTZ,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            """,
            logger: .init(label: "glue.migrations")
        )

        // Index on entity for fast lookups
        try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_glue_facts_entity ON glue_facts(entity)
            """,
            logger: .init(label: "glue.migrations")
        )

        // Composite index on entity + predicate
        try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_glue_facts_entity_predicate ON glue_facts(entity, predicate)
            """,
            logger: .init(label: "glue.migrations")
        )
    }

    /// Create a vector index for the given dimensions.
    /// Call this after the embedding dimensions are known.
    public static func createVectorIndex(
        connection: PostgresConnection,
        dimensions: Int,
        indexType: VectorIndexType = .default
    ) async throws {
        // Alter the embedding column to have the correct dimensions
        try await connection.query(
            PostgresQuery(unsafeSQL: """
                ALTER TABLE glue_frames
                ALTER COLUMN embedding TYPE vector(\(dimensions))
                """),
            logger: .init(label: "glue.migrations")
        )

        // Create index based on configuration
        let indexSQL: String
        switch indexType {
        case .ivfflat(let lists):
            indexSQL = """
                CREATE INDEX IF NOT EXISTS idx_glue_frames_embedding
                ON glue_frames USING ivfflat (embedding vector_cosine_ops)
                WITH (lists = \(lists))
                """
        case .hnsw(let m, let efConstruction):
            indexSQL = """
                CREATE INDEX IF NOT EXISTS idx_glue_frames_embedding
                ON glue_frames USING hnsw (embedding vector_cosine_ops)
                WITH (m = \(m), ef_construction = \(efConstruction))
                """
        }

        try await connection.query(
            PostgresQuery(unsafeSQL: indexSQL),
            logger: .init(label: "glue.migrations")
        )
    }
}
