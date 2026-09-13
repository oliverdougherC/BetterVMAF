import SwiftUI

struct VMAFGraphView: View {
    let frameMetrics: [VMAFCalculator.FrameMetric]
    var resultID: UUID? = nil
    var selectedTime: Double? = nil
    var onSeek: ((Double) -> Void)? = nil
    @State private var points: [TimelinePoint] = []
    @State private var preparedRevision: UUID?

    var body: some View {
        MetricTimelineView(points: points, name: "VMAF", unit: "points", revision: preparedRevision,
                           selectedTime: selectedTime, onSeek: onSeek)
            .task(id: resultID) {
                let raw = frameMetrics
                let preparation = Task.detached(priority: .userInitiated) { () -> [TimelinePoint] in
                    var output: [TimelinePoint] = []
                    var segment = 0
                    for frame in raw {
                        guard !Task.isCancelled else { return [] }
                        guard frame.timestamp.isFinite, frame.vmafScore.isFinite else { segment += 1; continue }
                        output.append(TimelinePoint(id: frame.frameNumber, time: frame.timestamp, value: frame.vmafScore, segment: segment))
                    }
                    return output
                }
                let prepared = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
                guard !Task.isCancelled else { return }
                points = prepared
                preparedRevision = UUID()
            }
    }
}
