import Foundation

/// A fact triple: entity + predicate + value, with optional evidence and time range.
public struct StructuredFact: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let entity: EntityKey
    public let predicate: PredicateKey
    public var value: FactValue
    public var evidence: StructuredEvidence?
    public var timeRange: StructuredTimeRange?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        entity: EntityKey,
        predicate: PredicateKey,
        value: FactValue,
        evidence: StructuredEvidence? = nil,
        timeRange: StructuredTimeRange? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.entity = entity
        self.predicate = predicate
        self.value = value
        self.evidence = evidence
        self.timeRange = timeRange
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Evidence linking a fact to its source memory frame.
public struct StructuredEvidence: Sendable, Codable, Equatable {
    public let frameId: UUID
    public let excerpt: String?

    public init(frameId: UUID, excerpt: String? = nil) {
        self.frameId = frameId
        self.excerpt = excerpt
    }
}

/// An optional time range for temporal facts.
public struct StructuredTimeRange: Sendable, Codable, Equatable {
    public let start: Date?
    public let end: Date?

    public init(start: Date? = nil, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}
