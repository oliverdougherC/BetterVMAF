import Foundation

/// Published as one value: cached marks can never carry another measurement's label/revision.
struct ComparisonTimelineSnapshot: Sendable {
    let revision = UUID()
    let runID: UUID
    let metricID: String
    let points: [TimelinePoint]

    func matches(runID: UUID, metricID: String) -> Bool { self.runID == runID && self.metricID == metricID }

    static func prepare(_ analysis: AnalysisResult, metricID: String) -> Self {
        var points: [TimelinePoint] = []
        points.reserveCapacity(analysis.samples.count)
        var segment = 0
        for (index, sample) in analysis.samples.enumerated() {
            if index % 4096 == 0 && Task.isCancelled { break }
            if let value = sample.values[metricID]?.finiteValue {
                points.append(TimelinePoint(id: sample.pair.index, time: sample.pair.timestamp, value: value, segment: segment))
            } else { segment += 1 }
        }
        return Self(runID: analysis.runID, metricID: metricID, points: points)
    }
}
