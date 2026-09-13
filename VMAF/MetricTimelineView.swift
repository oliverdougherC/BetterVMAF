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
    var timeDomain: ClosedRange<Double>? = nil
    @State private var plotted: [TimelinePoint] = []
    @State private var domain: ClosedRange<Double> = 0...1
    @State private var singletonSegments: Set<Int> = []
    @State private var hovered: TimelinePoint?
    @State private var zoom = 1.0
    @State private var position = 0.0

    private var fullRange: ClosedRange<Double> {
        TimelineData.timeRange(points, coverage: timeDomain)
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
                        LineMark(x: .value("Time (seconds)", point.time), y: .value(name, point.value), series: .value("Finite interval", point.segment))
                            .foregroundStyle(Color.accentColor)
                        if singletonSegments.contains(point.segment) {
                            PointMark(x: .value("Time (seconds)", point.time), y: .value(name, point.value))
                                .foregroundStyle(Color.accentColor)
                        }
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
                .overlay {
                    if points.isEmpty {
                        Text("No finite values to plot").foregroundStyle(.secondary)
                            .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .allowsHitTesting(false)
                    }
                }
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
                                if let time = time(at: event.location, proxy: proxy, geometry: overlay) { onSeek?(time) }
                            })
                    }
                }
                .task(id: PreparationKey(revision: revision, width: Int(geometry.size.width), range: visibleRange)) {
                    let input = points
                    let range = visibleRange
                    let buckets = max(32, min(1000, Int(geometry.size.width)))
                    let preparation = Task.detached(priority: .userInitiated) {
                        let reduced = TimelineData.envelope(input, range: range, buckets: buckets)
                        let counts = Dictionary(grouping: reduced, by: \.segment).mapValues(\.count)
                        return (reduced, Set(counts.filter { $0.value == 1 }.keys))
                    }
                    let result = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
                    guard !Task.isCancelled else { return }
                    plotted = result.0
                    singletonSegments = result.1
                }
                .task(id: revision) {
                    let input = points
                    let preparation = Task.detached(priority: .utility) { TimelineData.domain(input) }
                    let prepared = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
                    guard !Task.isCancelled else { return }
                    domain = prepared
                }
                .accessibilityLabel("\(name) timeline, \(points.count) finite measured values. Higher and lower values use the metric's native scale.")
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
        guard let selectedTime = time(at: location, proxy: proxy, geometry: geometry),
              let point = TimelineData.nearest(points, time: selectedTime),
              let anchor = proxy.plotFrame, let x = proxy.position(forX: point.time),
              abs(x + geometry[anchor].minX - location.x) <= 12 else { return nil }
        return point
    }

    private func time(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Double? {
        guard let anchor = proxy.plotFrame else { return nil }
        let plot = geometry[anchor]
        guard plot.contains(location), let time: Double = proxy.value(atX: location.x - plot.minX) else { return nil }
        return time
    }

    private struct PreparationKey: Hashable {
        let revision: UUID?
        let width: Int
        let range: ClosedRange<Double>
    }
}
