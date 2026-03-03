/// Protocol for collecting operational metrics from Glue.
public protocol MetricsCollector: Sendable {
    func recordSearchLatency(_ duration: Duration, mode: SearchMode) async
    func recordIngestLatency(_ duration: Duration) async
    func recordSearchResultCount(_ count: Int, mode: SearchMode) async
    func recordEmbeddingLatency(_ duration: Duration) async
    func recordRAGBuildLatency(_ duration: Duration) async
}
