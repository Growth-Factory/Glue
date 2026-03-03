/// Protocol for pluggable token counting strategies.
/// Implementations estimate the number of tokens in a text string.
public protocol TokenCounting: Sendable {
    func count(_ text: String) -> Int
}
