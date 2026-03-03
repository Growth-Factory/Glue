import Logging

/// A `MetricsCollector` that logs metrics via swift-log.
public struct LoggingMetricsCollector: MetricsCollector, Sendable {
    private let logger: Logger

    public init(logger: Logger = Logger(label: "glue.metrics")) {
        self.logger = logger
    }

    public func recordSearchLatency(_ duration: Duration, mode: SearchMode) async {
        logger.info("search_latency", metadata: [
            "duration_ms": "\(duration.milliseconds)",
            "mode": "\(mode)",
        ])
    }

    public func recordIngestLatency(_ duration: Duration) async {
        logger.info("ingest_latency", metadata: [
            "duration_ms": "\(duration.milliseconds)",
        ])
    }

    public func recordSearchResultCount(_ count: Int, mode: SearchMode) async {
        logger.info("search_result_count", metadata: [
            "count": "\(count)",
            "mode": "\(mode)",
        ])
    }

    public func recordEmbeddingLatency(_ duration: Duration) async {
        logger.info("embedding_latency", metadata: [
            "duration_ms": "\(duration.milliseconds)",
        ])
    }

    public func recordRAGBuildLatency(_ duration: Duration) async {
        logger.info("rag_build_latency", metadata: [
            "duration_ms": "\(duration.milliseconds)",
        ])
    }
}

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
