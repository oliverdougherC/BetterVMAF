import Foundation
import CryptoKit

/// Comparable candidates must share the source, viewing/normalization contract and exact coverage.
enum ComparisonTradeoffs {
    static func compatibilityKey(_ result: AnalysisResult) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var hash = SHA256()
        let metadata = [result.reference.sha256, result.modelSHA256, result.engineSHA256,
                        String(result.schemaVersion), String(result.comparedDuration)]
        hash.update(data: try encoder.encode(metadata))
        hash.update(data: try encoder.encode(result.configuration))
        hash.update(data: try encoder.encode(result.preprocessing))
        hash.update(data: try encoder.encode(result.definitions))
        for (index, sample) in result.samples.enumerated() {
            if index % 1024 == 0 { try Task.checkCancellation() }
            hash.update(data: try encoder.encode([sample.pair.timestamp, sample.pair.duration, sample.pair.referenceTimestamp]))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func nativeValue(_ id: String, in result: AnalysisResult) -> MetricValue? {
        result.aggregateMetrics[id] ?? result.pooledMetrics[id]?[id.hasPrefix("xpsnr_") ? "native_average" : "mean"]
    }
    static func rankingDefinitions(_ result: AnalysisResult) -> [MetricDefinition] {
        result.definitions.filter { $0.id != "cambi_source" && $0.id != "cambi_encode" }
    }
    static func dominates(_ lhs: AnalysisResult, _ rhs: AnalysisResult) -> Bool {
        guard lhs.comparison.byteCount <= rhs.comparison.byteCount else { return false }
        var strictlyBetter = lhs.comparison.byteCount < rhs.comparison.byteCount
        guard !rankingDefinitions(rhs).isEmpty else { return false }
        for definition in rankingDefinitions(rhs) {
            guard let a = nativeValue(definition.id, in: lhs)?.doubleValue,
                  let b = nativeValue(definition.id, in: rhs)?.doubleValue, !a.isNaN, !b.isNaN else { return false }
            if ["lower", "lower-is-better"].contains(definition.direction) {
                if a > b { return false }; strictlyBetter = strictlyBetter || a < b
            } else if ["higher", "higher-is-better"].contains(definition.direction) {
                if a < b { return false }; strictlyBetter = strictlyBetter || a > b
            } else { return false }
        }
        return strictlyBetter
    }
}
