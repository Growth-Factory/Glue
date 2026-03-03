import Foundation

/// Naive BM25-style text search index for in-memory use.
public actor InMemoryTextIndex: Sendable {
    private var documents: [UUID: String] = [:]
    private var tokenizedDocuments: [UUID: [String: Int]] = [:]
    private var documentFrequency: [String: Int] = [:]
    private var averageDocLength: Double = 0

    // BM25 parameters
    private let k1: Double = 1.2
    private let b: Double = 0.75

    public init() {}

    public func index(frameId: UUID, content: String) {
        // Remove old document if re-indexing
        if tokenizedDocuments[frameId] != nil {
            removeFromIndex(frameId: frameId)
        }

        documents[frameId] = content
        let tokens = tokenize(content)
        var termFreqs: [String: Int] = [:]
        for token in tokens {
            termFreqs[token, default: 0] += 1
        }
        tokenizedDocuments[frameId] = termFreqs

        for term in termFreqs.keys {
            documentFrequency[term, default: 0] += 1
        }

        recalculateAverageLength()
    }

    public func remove(frameId: UUID) {
        removeFromIndex(frameId: frameId)
    }

    public func search(query: String, topK: Int) -> [TextSearchResult] {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty, !documents.isEmpty else { return [] }

        let n = Double(documents.count)
        var scores: [(UUID, Float)] = []

        for (docId, termFreqs) in tokenizedDocuments {
            let docLength = Double(termFreqs.values.reduce(0, +))
            var score: Double = 0

            for token in queryTokens {
                guard let tf = termFreqs[token] else { continue }
                let df = Double(documentFrequency[token] ?? 0)
                let idf = log((n - df + 0.5) / (df + 0.5) + 1.0)
                let tfNorm = (Double(tf) * (k1 + 1.0)) /
                    (Double(tf) + k1 * (1.0 - b + b * docLength / max(averageDocLength, 1.0)))
                score += idf * tfNorm
            }

            if score > 0 {
                scores.append((docId, Float(score)))
            }
        }

        scores.sort { $0.1 > $1.1 }
        let topResults = scores.prefix(topK)

        return topResults.map { (id, score) in
            TextSearchResult(
                frameId: id,
                score: score,
                snippet: documents[id] ?? ""
            )
        }
    }

    // MARK: - Private

    private func removeFromIndex(frameId: UUID) {
        if let oldTermFreqs = tokenizedDocuments[frameId] {
            for term in oldTermFreqs.keys {
                if let count = documentFrequency[term] {
                    if count <= 1 {
                        documentFrequency.removeValue(forKey: term)
                    } else {
                        documentFrequency[term] = count - 1
                    }
                }
            }
        }
        documents.removeValue(forKey: frameId)
        tokenizedDocuments.removeValue(forKey: frameId)
        recalculateAverageLength()
    }

    private func recalculateAverageLength() {
        guard !tokenizedDocuments.isEmpty else {
            averageDocLength = 0
            return
        }
        let totalTokens = tokenizedDocuments.values.reduce(0) { $0 + $1.values.reduce(0, +) }
        averageDocLength = Double(totalTokens) / Double(tokenizedDocuments.count)
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
