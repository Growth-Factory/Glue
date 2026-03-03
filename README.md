# Glue

Swift library for AI agent memory. Store, search, and recall information using text search (BM25), vector similarity, hybrid retrieval, structured knowledge graphs, and RAG context building.

Designed for server-side Swift and Linux. Uses PostgreSQL + pgvector for production and an in-memory backend for testing -- no Apple-only dependencies.

## Features

- **Remember / Recall** -- Store and retrieve memory frames with metadata
- **Text Search** -- BM25-ranked full-text search (in-memory or PostgreSQL tsvector)
- **Vector Search** -- Cosine similarity over embeddings (in-memory brute-force or pgvector)
- **Hybrid Search** -- Reciprocal Rank Fusion combining text and vector results
- **Structured Memory** -- Knowledge graph with entity/predicate/value fact triples
- **RAG Context** -- Token-budgeted context assembly from search results
- **LLM Enhancement** -- Optional query expansion and surrogate generation via AnyLanguageModel

## Requirements

- Swift 6.2+
- macOS 14+ or Linux
- PostgreSQL 16 with pgvector (production) or no external dependencies (in-memory)

## Installation

Add Glue to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/aspect-build/Glue.git", from: "0.1.0"),
]
```

Then add the targets you need:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "GlueMemory", package: "Glue"),      // Core (required)
        .product(name: "GluePostgres", package: "Glue"),     // PostgreSQL backend
        .product(name: "GlueLLM", package: "Glue"),          // LLM enhancements
    ]
)
```

**GlueMemory** is the only required target. It includes the in-memory backend, all types, protocols, search logic, and RAG. Add **GluePostgres** for production storage and **GlueLLM** for LLM-powered query expansion.

## Quick Start

### In-Memory (No Database)

```swift
import GlueMemory

let backend = InMemoryStorageBackend()
let memory = MemoryOrchestrator(
    backend: backend,
    config: OrchestratorConfig(enableTextSearch: true, enableVectorSearch: false)
)

// Store some memories
try await memory.remember("Sarah's birthday is March 15th. She loves dark chocolate.")
try await memory.remember("Meeting with Acme Corp on Friday to discuss the Q2 roadmap.")
try await memory.remember("The deployment pipeline uses ArgoCD for continuous delivery.")

// Search
let results = try await memory.search(SearchRequest(query: "Sarah birthday gift ideas"))
print(results.results.first?.content ?? "No results")
// -> "Sarah's birthday is March 15th. She loves dark chocolate."
```

### With PostgreSQL

```swift
import GlueMemory
import GluePostgres

let config = try PostgresConfig.from(url: "postgres://glue:glue@localhost:5432/glue_db")
let backend = PostgresStorageBackend(config: config)

let memory = MemoryOrchestrator(backend: backend)
try await memory.initialize()

try await memory.remember("Our API rate limit is 1000 req/min per key.")
let results = try await memory.search(SearchRequest(query: "rate limiting"))

try await memory.shutdown()
```

## Usage Guide

### Storing and Retrieving Memories

Every piece of content is stored as a `MemoryFrame` -- a content string with optional metadata and embeddings.

```swift
// Store with metadata for filtering
let frame = try await memory.remember(
    "The database password rotates every 90 days.",
    metadata: ["category": "security", "team": "platform"]
)

// Retrieve by ID
let recalled = try await memory.recall(id: frame.id)

// List all frames, optionally filtered by metadata
let securityDocs = try await memory.listFrames(metadata: ["category": "security"])

// Delete
try await memory.forget(id: frame.id)
```

### Search Modes

```swift
// Text-only search (BM25 keyword matching)
let textResults = try await memory.search(SearchRequest(
    query: "database password rotation",
    mode: .textOnly,
    topK: 5
))

// Vector-only search (requires an EmbeddingProvider)
let vectorResults = try await memory.search(SearchRequest(
    query: "credential management policy",
    mode: .vectorOnly,
    topK: 5
))

// Hybrid search -- combines text and vector with Reciprocal Rank Fusion
let hybridResults = try await memory.search(SearchRequest(
    query: "how do we handle secrets",
    mode: .hybrid(alpha: 0.6), // 0.6 = 60% text weight, 40% vector weight
    topK: 5
))

// Filter by minimum score
let highConfidence = try await memory.search(SearchRequest(
    query: "deployment process",
    mode: .textOnly,
    topK: 10,
    minScore: 2.0
))
```

### Structured Memory (Knowledge Graph)

Store facts as entity/predicate/value triples with optional evidence linking back to source frames.

```swift
// Store facts
try await memory.addFact(
    entity: "Sarah",
    predicate: "birthday",
    value: .string("March 15")
)

try await memory.addFact(
    entity: "Sarah",
    predicate: "likes",
    value: .string("dark chocolate")
)

try await memory.addFact(
    entity: "Meridian Project",
    predicate: "deadline",
    value: .string("April 30"),
    evidence: StructuredEvidence(frameId: someFrameId, excerpt: "deadline is April 30th")
)

// Query facts
let sarahFacts = try await memory.facts(for: "Sarah")
// -> [birthday: "March 15", likes: "dark chocolate"]

let deadline = try await memory.facts(for: "Meridian Project", predicate: "deadline")
// -> [deadline: "April 30"]

// List all known entities
let entities = try await memory.listEntities()
// -> ["Sarah", "Meridian Project"]

// Delete a fact
try await memory.deleteFact(id: sarahFacts[0].id)
```

### RAG Context Building

Build token-budgeted context from search results to pass to an LLM.

```swift
let context = try await memory.buildRAGContext(
    query: "What is our deployment process?",
    mode: .textOnly,
    topK: 5,
    tokenBudget: 2048
)

// Use in an LLM prompt
let prompt = """
Answer the question using the context below.

Context:
\(context.rendered)

Question: What is our deployment process?
"""

print("Total tokens used: \(context.totalTokens)")
print("Number of context items: \(context.items.count)")
```

### Bringing Your Own Embeddings

Glue does not ship a built-in embedder. Implement the `EmbeddingProvider` protocol to plug in any embedding service.

```swift
import GlueMemory

struct OpenAIEmbedder: EmbeddingProvider {
    let apiKey: String

    var dimensions: Int { 1536 }
    var normalize: Bool { true }
    var identity: EmbeddingIdentity {
        EmbeddingIdentity(provider: "openai", model: "text-embedding-3-small", dimensions: 1536)
    }

    func embed(_ text: String) async throws -> [Float] {
        // Call OpenAI embeddings API and return the vector as [Float]
    }
}

let memory = MemoryOrchestrator(
    backend: backend,
    embeddingProvider: OpenAIEmbedder(apiKey: "sk-..."),
    config: OrchestratorConfig(enableTextSearch: true, enableVectorSearch: true)
)
```

With an embedding provider, `remember()` automatically generates and stores embeddings. Vector and hybrid search modes become available.

### LLM-Enhanced Search

Use AnyLanguageModel to expand queries and generate text surrogates.

```swift
import GlueMemory
import GlueLLM
import AnyLanguageModel

let model: any LanguageModel = ... // Your language model
let enhancer = AnyLanguageModelEnhancer(model: model)

let memory = MemoryOrchestrator(
    backend: backend,
    llmEnhancer: enhancer,
    config: OrchestratorConfig(
        enableSurrogateGeneration: true,  // Generate summaries at ingest
        enableQueryExpansion: true         // Expand queries at search time
    )
)
```

Both features are independently controllable:

- **Surrogate generation** (`enableSurrogateGeneration`) -- at `remember()` time, the LLM generates a summary/keywords that get appended to the stored content. This helps BM25 match when the user's query uses different words than the original content. Adds latency to ingest.
- **Query expansion** (`enableQueryExpansion`) -- at `search()` time, the LLM rewrites the query into multiple variants. Each variant is searched independently and results are merged by best score per frame. Adds latency to search.

You can enable either, both, or neither. Both default to `false`.

## Configuration

```swift
let config = OrchestratorConfig(
    enableTextSearch: true,              // Enable BM25 text search (default: true)
    enableVectorSearch: true,            // Enable vector similarity search (default: true)
    defaultSearchMode: .hybrid,          // Default search mode (default: .hybrid)
    defaultTopK: 10,                     // Default number of results (default: 10)
    chunkingStrategy: .tokenCount(       // How to chunk long texts
        targetTokens: 256,
        overlapTokens: 32
    ),
    ragTokenBudget: 4096,                // Max tokens for RAG context (default: 4096)
    enableSurrogateGeneration: false,    // LLM summary at ingest (default: false)
    surrogateMaxTokens: 128,             // Max tokens for surrogate (default: 128)
    enableQueryExpansion: false           // LLM query expansion at search (default: false)
)
```

## PostgreSQL Setup

### Docker (Recommended for Development)

```bash
docker compose up -d
```

This starts PostgreSQL 16 with pgvector on port 5432 (user: `glue`, password: `glue`, database: `glue_test`).

### Manual Setup

1. Install PostgreSQL 16+ with the [pgvector](https://github.com/pgvector/pgvector) extension.
2. Create a database:

```sql
CREATE DATABASE glue_db;
\c glue_db
CREATE EXTENSION vector;
```

3. Connect:

```swift
// From a URL
let config = try PostgresConfig.from(url: "postgres://user:pass@localhost:5432/glue_db")

// Or manually
let config = PostgresConfig(
    host: "localhost",
    port: 5432,
    username: "glue",
    password: "glue",
    database: "glue_db"
)
```

Tables and indexes are created automatically when you call `initialize()`.

## Architecture

```
+-------------------------------------------------+
|               MemoryOrchestrator                |
|         (actor -- main public API)              |
|                                                 |
|  remember / recall / search / buildRAGContext   |
|  addFact / facts / deleteFact / listEntities   |
+---------+--------------+-----------+------------+
          |              |           |
   StorageBackend  EmbeddingProvider LLMEnhancer
   (protocol)      (protocol)       (protocol)
          |              |           |
+---------+--------------+-----------+------------+
|                                                 |
|  InMemoryStorageBackend   PostgresStorageBackend|
|  (BM25 + cosine sim)     (tsvector + pgvector)  |
|                                                 |
|              AnyLanguageModelEnhancer           |
|              (query expansion, surrogates)      |
+-------------------------------------------------+
```

- **`StorageBackend`** -- Central protocol enabling pluggable backends. InMemory for tests, Postgres for production.
- **`EmbeddingProvider`** -- You supply your own embedder (OpenAI, Ollama, etc.).
- **`LLMEnhancer`** -- Optional query expansion and surrogate generation.
- All mutable state lives in actors. All types are `Sendable`.

## Building and Testing

```bash
# Build all targets
swift build

# Unit tests -- no database required
swift test --filter GlueMemoryTests

# LLM tests -- uses mock model, no API key required
swift test --filter GlueLLMTests

# PostgreSQL integration tests -- requires running database
docker compose up -d
GLUE_TEST_POSTGRES_URL="postgres://glue:glue@localhost:5432/glue_test" swift test --filter GluePostgresTests

# All tests
GLUE_TEST_POSTGRES_URL="postgres://glue:glue@localhost:5432/glue_test" swift test
```

### Relevance Benchmarks

The test suite includes relevance benchmark tests that verify search quality across realistic scenarios:

- **Engineering Wiki** -- 10 internal docs (incident response, deploy process, database runbook, etc.) with disambiguation queries
- **Personal Assistant** -- 10 personal memories (family, health, travel, etc.) testing recall with vague and specific queries
- **Codebase Documentation** -- 10 module docs sharing vocabulary (Redis, PostgreSQL, Elasticsearch appear in multiple) testing precise retrieval
- **Pitch Deck** -- 13 slides (problem, solution, team, advisors, financials, etc.) testing team/advisor disambiguation and person-specific retrieval

These benchmarks run with the in-memory backend and require no external services:

```bash
swift test --filter RelevanceBenchmark
```

## Package Structure

| Target | Description | Dependencies |
|--------|-------------|--------------|
| **GlueMemory** | Core types, protocols, in-memory backend, search, RAG | swift-log |
| **GluePostgres** | PostgreSQL storage backend | GlueMemory, postgres-nio |
| **GlueLLM** | LLM integration via AnyLanguageModel | GlueMemory, AnyLanguageModel |

## License

MIT
