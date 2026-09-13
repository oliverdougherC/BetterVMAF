import SwiftUI
import Charts

/// Immutable input for a view lifetime. Change `revision` when replacing its samples.
struct MetricTimelineView: View {
    let points: [TimelinePoint]
    let name: String
    let unit: String
    var revision: UUID? = nil
    var selectedTime: Double? = nil
    var onSeek: ((Double) -> Void)? = nil
    @State private var plotted: [TimelinePoint] = []
    @State private var domain: ClosedRange<Double> = 0...1
    @State private var hovered: TimelinePoint?
    @State private var zoom = 1.0
    @State private var position = 0.0

    private var fullRange: ClosedRange<Double> {
        let start = points.first?.time ?? 0
        let end = points.last?.time ?? 1
        return start...max(start + 0.001, end)
    }
    private var visibleRange: ClosedRange<Double> {
        let span = fullRange.upperBound - fullRange.lowerBound
        let width = span / zoom
        let start = fullRange.lowerBound + position * (span - width)
        return start...(start + width)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(name) over time").font(.headline)
                Spacer()
                if let hovered {
                    Text("\(hovered.time, specifier: "%.3f") s · \(hovered.value, specifier: "%.2f") \(unit)")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            GeometryReader { geometry in
                Chart {
                    ForEach(plotted) { point in
                        LineMark(x: .value("Time (seconds)", point.time), y: .value(name, point.value))
                            .foregroundStyle(Color.accentColor)
                    }
                    if plotted.count == 1, let point = plotted.first {
                        PointMark(x: .value("Time (seconds)", point.time), y: .value(name, point.value))
                    }
                    if let selectedTime, visibleRange.contains(selectedTime) {
                        RuleMark(x: .value("Selected frame", selectedTime)).foregroundStyle(.secondary)
                    }
                }
                .chartXScale(domain: visibleRange)
                .chartYScale(domain: domain)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                .chartXAxisLabel("Seconds")
                .chartYAxisLabel(unit)
                .chartOverlay { proxy in
                    GeometryReader { overlay in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hovered = sample(at: location, proxy: proxy, geometry: overlay)
                                case .ended: hovered = nil
                                }
                            }
                            .gesture(SpatialTapGesture().onEnded { event in
                                if let point = sample(at: event.location, proxy: proxy, geometry: overlay) { onSeek?(point.time) }
                            })
                    }
                }
                .task(id: PreparationKey(revision: revision, width: Int(geometry.size.width), range: visibleRange)) {
                    let input = points
                    let range = visibleRange
                    let buckets = max(32, min(1000, Int(geometry.size.width)))
                    let preparation = Task.detached(priority: .userInitiated) {
                        (TimelineData.envelope(input, range: range, buckets: buckets), TimelineData.domain(input))
                    }
                    let result = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
                    guard !Task.isCancelled else { return }
                    plotted = result.0
                    domain = result.1
                }
                .accessibilityLabel("\(name) timeline, \(points.count) measured frames. Higher and lower values use the metric's native scale.")
            }
            .frame(minHeight: 140, idealHeight: 180)
            HStack {
                Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom = max(1, zoom / 2) }
                    .labelStyle(.iconOnly).disabled(zoom == 1)
                Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom = min(64, zoom * 2) }
                    .labelStyle(.iconOnly).disabled(zoom == 64 || points.count < 2)
                if zoom > 1 {
                    Slider(value: $position, in: 0...1).accessibilityLabel("Timeline position")
                    Button("Reset") { zoom = 1; position = 0 }
                }
                Spacer()
                Text("Numeric scale · raw data preserved").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sample(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> TimelinePoint? {
        guard let anchor = proxy.plotFrame else { return nil }
        let plot = geometry[anchor]
        guard plot.contains(location), let time: Double = proxy.value(atX: location.x - plot.minX) else { return nil }
        return TimelineData.nearest(points, time: time)
    }

    private struct PreparationKey: Hashable {
        let revision: UUID?
        let width: Int
        let range: ClosedRange<Double>
    }
}
