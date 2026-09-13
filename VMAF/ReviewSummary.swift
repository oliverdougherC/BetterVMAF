import Foundation

struct ReviewConcern: Identifiable, Sendable {
    let id: String
    var start: Double
    var end: Double
    var firstFrame: Int
    var lastFrame: Int
    var reasons: [String]
    var kind: String
}

struct ReviewDistribution: Identifiable, Sendable {
    var id: String { metricID }
    let metricID: String
    let name: String
    let unit: String
    let validCount: Int
    let missingCount: Int
    let coverageSeconds: Double
    let durationWeightedMean: MetricValue
    let median: MetricValue
    let tail: MetricValue
    let extreme: MetricValue
    let tailLabel: String
}

struct ReviewObservation: Sendable {
    let frame: Int
    let time: Double
    let duration: Double
    let value: Double?
}

struct ReviewSummary: Sendable {
    let concerns: [ReviewConcern]
    let distributions: [ReviewDistribution]

    /// Run on a background task. Supplements, never replaces, native metric pooling.
    static func make(result: VMAFCalculator.VMAFResult) -> Self {
        guard let analysis = result.analysis else { return Self(concerns: [], distributions: []) }
        var distributions: [ReviewDistribution] = []
        var candidates: [ReviewConcern] = []
        // Feature logs retain many implementation signals. Review only named measurements.
        for definition in analysis.definitions {
            guard !Task.isCancelled else { return Self(concerns: [], distributions: []) }
            var observations: [ReviewObservation] = []
            observations.reserveCapacity(analysis.samples.count)
            for sample in analysis.samples {
                if sample.pair.index % 2048 == 0, Task.isCancelled { return Self(concerns: [], distributions: []) }
                observations.append(ReviewObservation(frame: sample.pair.index, time: sample.pair.timestamp, duration: sample.pair.duration,
                                  value: sample.values[definition.id]?.doubleValue))
            }
            let summary = summarize(observations, id: definition.id, name: definition.name,
                                    unit: definition.unit, lowerIsBetter: definition.direction == "lower")
            distributions.append(summary.0)
            candidates.append(contentsOf: summary.1)
        }
        let vmaf = candidates.filter { $0.id.hasPrefix("vmaf-") }
        let xpsnr = candidates.filter { $0.id.hasPrefix("xpsnr_") }
        if distributions.contains(where: { $0.metricID == "vmaf" && $0.validCount > 0 }),
           distributions.contains(where: { $0.metricID.hasPrefix("xpsnr_") && $0.validCount > 0 }) {
            for index in candidates.indices {
                let candidate = candidates[index]
                let alternatives: [ReviewConcern]
                let reason: String
                if candidate.id.hasPrefix("vmaf-") {
                    alternatives = xpsnr
                    reason = "VMAF tail differs from the selected XPSNR tail intervals; review the disagreement"
                } else if candidate.id.hasPrefix("xpsnr_") {
                    alternatives = vmaf
                    reason = "XPSNR tail differs from the selected VMAF tail intervals; review the disagreement"
                } else { continue }
                if !alternatives.contains(where: { $0.start < candidate.end && candidate.start < $0.end }) {
                    candidates[index].reasons.append(reason)
                }
            }
        }
        return Self(concerns: merge(candidates), distributions: distributions)
    }

    static func summarize(_ observations: [ReviewObservation], id: String, name: String, unit: String,
                          lowerIsBetter: Bool) -> (ReviewDistribution, [ReviewConcern]) {
        let cancelled = ReviewDistribution(metricID: id, name: name, unit: unit, validCount: 0, missingCount: observations.count,
            coverageSeconds: 0, durationWeightedMean: .unavailable, median: .unavailable, tail: .unavailable, extreme: .unavailable,
            tailLabel: lowerIsBetter ? "P95" : "P5")
        guard !Task.isCancelled else { return (cancelled, []) }
        let valid = observations.filter { $0.value != nil && !$0.value!.isNaN && $0.duration > 0 && $0.duration.isFinite }
        guard !Task.isCancelled else { return (cancelled, []) }
        let sorted = valid.sorted { $0.value! < $1.value! }
        guard !Task.isCancelled else { return (cancelled, []) }
        let duration = valid.reduce(0) { $0 + $1.duration }
        func quantile(_ fraction: Double) -> Double? {
            guard !sorted.isEmpty else { return nil }
            let target = fraction * duration
            var elapsed = 0.0
            for observation in sorted {
                elapsed += observation.duration
                if elapsed >= target { return observation.value }
            }
            return sorted.last?.value
        }
        let mean = duration > 0 ? valid.reduce(0) { $0 + $1.value! * ($1.duration / duration) } : nil
        let median = quantile(0.5)
        let tail = quantile(lowerIsBetter ? 0.95 : 0.05)
        let extreme = lowerIsBetter ? sorted.last?.value : sorted.first?.value
        let distribution = ReviewDistribution(metricID: id, name: name, unit: unit,
            validCount: valid.count, missingCount: observations.count - valid.count, coverageSeconds: duration,
            durationWeightedMean: mean.map(MetricValue.init) ?? .unavailable,
            median: median.map(MetricValue.init) ?? .unavailable, tail: tail.map(MetricValue.init) ?? .unavailable,
            extreme: extreme.map(MetricValue.init) ?? .unavailable, tailLabel: lowerIsBetter ? "P95" : "P5")
        guard let tail, let extreme, let median, sorted.first?.value != sorted.last?.value else { return (distribution, []) }
        var intervals: [ReviewConcern] = []
        var active: ReviewConcern?
        func finish() {
            if var current = active {
                current.kind = current.firstFrame == current.lastFrame ? "Isolated frame" : "Sustained interval"
                intervals.append(current)
            }
            active = nil
        }
        for observation in observations {
            if observation.frame % 2048 == 0, Task.isCancelled { return (cancelled, []) }
            guard let value = observation.value, !value.isNaN,
                  (lowerIsBetter ? value >= tail && value > median : value <= tail && value < median) else { finish(); continue }
            if var current = active, observation.frame == current.lastFrame + 1,
               abs(observation.time - current.end) < 0.0001 {
                current.end = observation.time + observation.duration
                current.lastFrame = observation.frame
                active = current
            } else {
                finish()
                active = ReviewConcern(id: "\(id)-\(observation.frame)", start: observation.time,
                    end: observation.time + observation.duration, firstFrame: observation.frame,
                    lastFrame: observation.frame, reasons: ["\(name): \(lowerIsBetter ? "upper" : "lower") duration-weighted tail"], kind: "")
            }
        }
        finish()
        // Prioritize the global extreme and longest continuous damage; deterministic ties.
        let worstFrame = valid.first { $0.value == extreme }?.frame
        // Separate ranking keeps score-scale values out of cross-metric comparisons.
        intervals.sort { a, b in
            let aWorst = worstFrame.map { a.firstFrame <= $0 && $0 <= a.lastFrame } ?? false
            let bWorst = worstFrame.map { b.firstFrame <= $0 && $0 <= b.lastFrame } ?? false
            if aWorst != bWorst { return aWorst }
            if a.end - a.start != b.end - b.start { return a.end - a.start > b.end - b.start }
            return a.start < b.start
        }
        return (distribution, Array(intervals.prefix(4)))
    }

    static func merge(_ concerns: [ReviewConcern]) -> [ReviewConcern] {
        var output: [ReviewConcern] = []
        for concern in concerns.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) {
            if var last = output.last, concern.start <= last.end + 0.25 {
                output.removeLast()
                last.end = max(last.end, concern.end)
                last.lastFrame = max(last.lastFrame, concern.lastFrame)
                last.reasons = Array(Set(last.reasons + concern.reasons)).sorted()
                last.kind = "Review interval"
                output.append(last)
            } else { output.append(concern) }
        }
        return output
    }
}
