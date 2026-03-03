# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glue is a Swift library for AI agent memory — matching Wax's API surface (remember/recall, search, structured memory, RAG) but Linux-compatible. It replaces Apple-only dependencies with PostgreSQL + pgvector and AnyLanguageModel.

## Package Structure

Three library targets:
- **GlueMemory** — Core types, protocols, in-memory backend, search/RAG logic (no DB dependency)
- **GluePostgres** — PostgreSQL `StorageBackend` implementation via postgres-nio + pgvector
- **GlueLLM** — AnyLanguageModel integration (query expansion, surrogate generation)

## Build & Test Commands

```bash
swift build                              # Build all targets
swift test --filter GlueMemoryTests      # Run unit tests (no DB required)
swift test --filter GlueLLMTests         # Run LLM tests (mock model)
swift test --filter GluePostgresTests    # Integration tests (requires GLUE_TEST_POSTGRES_URL)
swift test                               # Run all tests
```

## Architecture

- **`StorageBackend` protocol** — Central abstraction enabling pluggable backends (InMemory for tests, Postgres for production)
- **`MemoryOrchestrator` actor** — Main public API wiring storage, search, embeddings, and LLM enhancements
- **`EmbeddingProvider` protocol** — Users supply their own embedder (OpenAI, Ollama, etc.)
- **`LLMEnhancer` protocol** — Optional query expansion and surrogate generation via AnyLanguageModel
- All mutable state lives in actors; all types are `Sendable`

## Key File Locations

- Types: `Sources/GlueMemory/Types/`
- Protocols: `Sources/GlueMemory/Protocols/`
- In-memory backend: `Sources/GlueMemory/InMemory/`
- Search logic (RRF, chunking): `Sources/GlueMemory/Search/`
- RAG context: `Sources/GlueMemory/RAG/`
- PostgreSQL backend: `Sources/GluePostgres/`
- LLM integration: `Sources/GlueLLM/`

## Dependencies

- swift-tools-version: 6.2
- postgres-nio 1.21+
- swift-log 1.5+
- AnyLanguageModel 0.7+ (mattt/AnyLanguageModel)
- swift-testing 0.12+ (test only)

## Testing

Tests use Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`).
Relevance benchmark tests in `RelevanceBenchmarkTests.swift` verify that BM25 text search returns the correct documents for realistic queries — these are the primary quality assurance tests.
