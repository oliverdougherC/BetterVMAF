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
                let preparation = Task.detached(priority: .userInitiated) {
                    raw.compactMap { frame -> TimelinePoint? in
                        guard frame.timestamp.isFinite, frame.vmafScore.isFinite else { return nil }
                        return TimelinePoint(id: frame.frameNumber, time: frame.timestamp, value: frame.vmafScore)
                    }
                }
                let prepared = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
                guard !Task.isCancelled else { return }
                points = prepared
                preparedRevision = UUID()
            }
    }
}
