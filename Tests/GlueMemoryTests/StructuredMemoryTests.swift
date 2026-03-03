import Testing
import Foundation
@testable import GlueMemory

@Suite("StructuredMemory")
struct StructuredMemoryTests {
    @Test func storeFetchFacts() async throws {
        let backend = InMemoryStorageBackend()

        let fact = StructuredFact(
            entity: "alice",
            predicate: "age",
            value: .int(30)
        )

        try await backend.storeFact(fact)
        let facts = try await backend.fetchFacts(entity: "alice")

        #expect(facts.count == 1)
        #expect(facts[0].value == .int(30))
        #expect(facts[0].predicate == PredicateKey("age"))
    }

    @Test func fetchByPredicate() async throws {
        let backend = InMemoryStorageBackend()

        try await backend.storeFact(StructuredFact(entity: "alice", predicate: "age", value: .int(30)))
        try await backend.storeFact(StructuredFact(entity: "alice", predicate: "city", value: .string("NYC")))
        try await backend.storeFact(StructuredFact(entity: "bob", predicate: "age", value: .int(25)))

        let aliceAge = try await backend.fetchFacts(entity: "alice", predicate: "age")
        #expect(aliceAge.count == 1)
        #expect(aliceAge[0].value == .int(30))

        let aliceFacts = try await backend.fetchFacts(entity: "alice")
        #expect(aliceFacts.count == 2)
    }

    @Test func deleteFact() async throws {
        let backend = InMemoryStorageBackend()

        let fact = StructuredFact(entity: "alice", predicate: "age", value: .int(30))
        try await backend.storeFact(fact)
        try await backend.deleteFact(id: fact.id)

        let facts = try await backend.fetchFacts(entity: "alice")
        #expect(facts.isEmpty)
    }

    @Test func updateFact() async throws {
        let backend = InMemoryStorageBackend()

        let fact = StructuredFact(entity: "alice", predicate: "age", value: .int(30))
        try await backend.storeFact(fact)

        let updated = StructuredFact(
            id: fact.id,
            entity: fact.entity,
            predicate: fact.predicate,
            value: .int(31),
            createdAt: fact.createdAt,
            updatedAt: Date()
        )
        try await backend.updateFact(updated)

        let facts = try await backend.fetchFacts(entity: "alice")
        #expect(facts.count == 1)
        #expect(facts[0].value == .int(31))
    }

    @Test func listEntities() async throws {
        let backend = InMemoryStorageBackend()

        try await backend.storeFact(StructuredFact(entity: "alice", predicate: "age", value: .int(30)))
        try await backend.storeFact(StructuredFact(entity: "bob", predicate: "age", value: .int(25)))
        try await backend.storeFact(StructuredFact(entity: "alice", predicate: "city", value: .string("NYC")))

        let entities = try await backend.listEntities()
        #expect(entities.count == 2)
        #expect(Set(entities) == Set([EntityKey("alice"), EntityKey("bob")]))
    }
}
