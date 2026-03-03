import Testing
import Foundation
@testable import GlueMemory

@Suite("Types")
struct TypeTests {
    @Test func memoryFrameCodable() throws {
        let frame = MemoryFrame(
            content: "Hello world",
            metadata: ["source": "test", "category": "greeting"],
            embedding: [0.1, 0.2, 0.3]
        )

        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(MemoryFrame.self, from: data)

        #expect(decoded.id == frame.id)
        #expect(decoded.content == frame.content)
        #expect(decoded.metadata == frame.metadata)
        #expect(decoded.embedding == frame.embedding)
    }

    @Test func factValueCodable() throws {
        let values: [FactValue] = [.string("hello"), .int(42), .double(3.14), .bool(true)]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(FactValue.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test func keyLiterals() {
        let entity: EntityKey = "user:alice"
        let predicate: PredicateKey = "likes"

        #expect(entity.rawValue == "user:alice")
        #expect(predicate.rawValue == "likes")
    }

    @Test func structuredFactCodable() throws {
        let fact = StructuredFact(
            entity: EntityKey("alice"),
            predicate: PredicateKey("age"),
            value: .int(30),
            evidence: StructuredEvidence(frameId: UUID(), excerpt: "Alice is 30"),
            timeRange: StructuredTimeRange(start: Date(), end: nil)
        )

        let data = try JSONEncoder().encode(fact)
        let decoded = try JSONDecoder().decode(StructuredFact.self, from: data)

        #expect(decoded.id == fact.id)
        #expect(decoded.entity == fact.entity)
        #expect(decoded.predicate == fact.predicate)
        #expect(decoded.value == fact.value)
    }

    @Test func searchModeCodable() throws {
        let modes: [SearchMode] = [.textOnly, .vectorOnly, .hybrid(alpha: 0.7)]
        for mode in modes {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SearchMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test func embeddingIdentityEquality() {
        let a = EmbeddingIdentity(provider: "openai", model: "text-embedding-3-small", dimensions: 1536)
        let b = EmbeddingIdentity(provider: "openai", model: "text-embedding-3-small", dimensions: 1536)
        let c = EmbeddingIdentity(provider: "ollama", model: "nomic-embed", dimensions: 768)

        #expect(a == b)
        #expect(a != c)
    }
}
