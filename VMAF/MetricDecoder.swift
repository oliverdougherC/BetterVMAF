import Foundation

/// Upstream libvmaf JSON. Only selected primary outputs are required; every optional numeric feature is retained.
struct MetricLog: Decodable, Sendable {
    struct Frame: Decodable, Sendable {
        let frameNum: Int
        let metrics: [String: MetricValue]
    }
    let version: String?
    let fps: Double?
    let frames: [Frame]
    let pooledMetrics: [String: [String: MetricValue]]
    let aggregateMetrics: [String: MetricValue]
    enum CodingKeys: String, CodingKey { case version, fps, frames; case pooledMetrics = "pooled_metrics", aggregateMetrics = "aggregate_metrics" }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        fps = try values.decodeIfPresent(Double.self, forKey: .fps)
        frames = try values.decode([Frame].self, forKey: .frames)
        pooledMetrics = try values.decodeIfPresent([String: [String: MetricValue]].self, forKey: .pooledMetrics) ?? [:]
        aggregateMetrics = try values.decodeIfPresent([String: MetricValue].self, forKey: .aggregateMetrics) ?? [:]
    }
    static func decode(_ data: Data, expectedCount: Int? = nil) throws -> MetricLog {
        let log = try JSONDecoder().decode(MetricLog.self, from: data)
        guard !log.frames.isEmpty else { throw AnalysisError.missingMetric("VMAF frames") }
        if let expectedCount, log.frames.count != expectedCount {
            throw AnalysisError.invalid("Metric coverage differs from decoded frame coverage (\(log.frames.count)/\(expectedCount)).")
        }
        for (index, frame) in log.frames.enumerated() {
            guard frame.frameNum == index, frame.metrics["vmaf"]?.finiteValue != nil else { throw AnalysisError.missingMetric("VMAF frame \(index)") }
        }
        guard log.pooledMetrics["vmaf"]?["mean"]?.finiteValue != nil else { throw AnalysisError.missingMetric("VMAF mean") }
        return log
    }
}

struct XPSNRLog: Sendable {
    let frames: [[String: MetricValue]]
    let planeAverages: [String: MetricValue]
    var minimumPlaneAverage: MetricValue {
        let values = planeAverages.values.compactMap(\.doubleValue)
        return values.count == 3 ? MetricValue(values.min()!) : .unavailable
    }
    static func parse(stats: String, stderr: String, expectedCount: Int) throws -> XPSNRLog {
        let pattern = #"([A-Za-z_]+):\s*([^\s]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        func fields(_ line: String) -> [String: String] {
            var output: [String: String] = [:]
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let key = Range(match.range(at: 1), in: line), let value = Range(match.range(at: 2), in: line) {
                    output[String(line[key])] = String(line[value])
                }
            }
            return output
        }
        func metric(_ text: String?) throws -> MetricValue {
            guard let text, let value = Double(text), !value.isNaN else { throw AnalysisError.missingMetric("XPSNR plane") }
            return MetricValue(value)
        }
        var frames: [[String: MetricValue]] = []
        for line in stats.split(separator: "\n") {
            let row = fields(String(line))
            guard let number = row["n"] else { continue }
            guard Int(number) == frames.count + 1 else { throw AnalysisError.invalid("XPSNR frame order is incomplete.") }
            frames.append(try Dictionary(uniqueKeysWithValues: ["y", "u", "v"].map { plane in
                ("xpsnr_\(plane)", try metric(row["XPSNR_\(plane)"] ?? row["xpsnr_\(plane)"] ?? row[plane]))
            }))
        }
        guard frames.count == expectedCount else { throw AnalysisError.invalid("XPSNR coverage differs from the evaluated frame map.") }
        // The pinned engine writes a complete native aggregate to its stats file.
        // av_log writes from other filters can interleave with the multi-part stderr summary.
        let fileSummary = stats.split(separator: "\n").last { $0.hasPrefix("XPSNR average,") }
        let diagnosticSummary = stderr.split(separator: "\n").last {
            $0.contains("XPSNR") && $0.contains(" y:") && $0.contains(" u:") && $0.contains(" v:") && !$0.contains("XPSNR y:")
        }
        guard let summary = fileSummary ?? diagnosticSummary else {
            throw AnalysisError.missingMetric("native XPSNR aggregate")
        }
        let average = fields(String(summary))
        let planes = try Dictionary(uniqueKeysWithValues: ["y", "u", "v"].map { ("xpsnr_\($0)", try metric(average[$0])) })
        return XPSNRLog(frames: frames, planeAverages: planes)
    }
}

/// Imports do not invent file identity, cadence or a model from the current UI selection.
struct LegacyMetricImport: Sendable {
    let provenanceStatus = "legacy-unknown"
    let modelIdentifier = "unknown (legacy log)"
    let frameTimingStatus = "unknown; frame index only"
    let log: MetricLog
    init(data: Data) throws { log = try MetricLog.decode(data) }
}
