import PostgresNIO

/// DDL migrations for Glue's PostgreSQL schema.
public enum PostgresMigrations: Sendable {
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
        dimensions: Int
    ) async throws {
        // Alter the embedding column to have the correct dimensions
        try await connection.query(
            PostgresQuery(unsafeSQL: """
                ALTER TABLE glue_frames
                ALTER COLUMN embedding TYPE vector(\(dimensions))
                """),
            logger: .init(label: "glue.migrations")
        )

        // Create IVFFlat index for vector similarity search
        try await connection.query("""
            CREATE INDEX IF NOT EXISTS idx_glue_frames_embedding
            ON glue_frames USING ivfflat (embedding vector_cosine_ops)
            WITH (lists = 100)
            """,
            logger: .init(label: "glue.migrations")
        )
    }
}
