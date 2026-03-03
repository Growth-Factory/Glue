import Foundation

/// A single unit of stored memory content.
public struct MemoryFrame: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var content: String
    public var metadata: [String: String]
    public var embedding: [Float]?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        content: String,
        metadata: [String: String] = [:],
        embedding: [Float]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.metadata = metadata
        self.embedding = embedding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
