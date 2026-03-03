import Foundation

/// Errors thrown by the Glue library.
public enum GlueError: Error, Sendable, LocalizedError {
    case frameNotFound(UUID)
    case embeddingDimensionMismatch(expected: Int, got: Int)
    case embeddingProviderRequired
    case backendError(String)
    case invalidConfiguration(String)
    case entityNotFound(EntityKey)
    case factNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .frameNotFound(let id):
            return "Memory frame not found: \(id)"
        case .embeddingDimensionMismatch(let expected, let got):
            return "Embedding dimension mismatch: expected \(expected), got \(got)"
        case .embeddingProviderRequired:
            return "An EmbeddingProvider is required for vector search"
        case .backendError(let msg):
            return "Backend error: \(msg)"
        case .invalidConfiguration(let msg):
            return "Invalid configuration: \(msg)"
        case .entityNotFound(let key):
            return "Entity not found: \(key.rawValue)"
        case .factNotFound(let id):
            return "Fact not found: \(id)"
        }
    }
}
