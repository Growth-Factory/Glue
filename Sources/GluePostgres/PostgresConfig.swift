import Foundation
import PostgresNIO
import GlueMemory

/// Configuration for connecting to PostgreSQL.
public struct PostgresConfig: Sendable {
    public let host: String
    public let port: Int
    public let username: String
    public let password: String?
    public let database: String
    public let tls: PostgresConnection.Configuration.TLS
    public let vectorIndexType: VectorIndexType
    public let minConnections: Int
    public let maxConnections: Int

    public init(
        host: String = "localhost",
        port: Int = 5432,
        username: String = "postgres",
        password: String? = nil,
        database: String = "glue",
        tls: PostgresConnection.Configuration.TLS = .disable,
        vectorIndexType: VectorIndexType = .default,
        minConnections: Int = 0,
        maxConnections: Int = 20
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.tls = tls
        self.vectorIndexType = vectorIndexType
        self.minConnections = minConnections
        self.maxConnections = maxConnections
    }

    /// Parse from a PostgreSQL connection URL.
    public static func from(url: String) throws -> PostgresConfig {
        guard let components = URLComponents(string: url) else {
            throw PostgresConfigError.invalidURL(url)
        }
        return PostgresConfig(
            host: components.host ?? "localhost",
            port: components.port ?? 5432,
            username: components.user ?? "postgres",
            password: components.password,
            database: String(components.path.dropFirst()),
            tls: .disable
        )
    }

    var connectionConfig: PostgresConnection.Configuration {
        PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: tls
        )
    }

    /// Build a ``PostgresClient.Configuration`` with connection pooling options.
    public var clientConfiguration: PostgresClient.Configuration {
        var config = PostgresClient.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
        config.options.minimumConnections = minConnections
        config.options.maximumConnections = maxConnections
        return config
    }
}

enum PostgresConfigError: Error {
    case invalidURL(String)
}
