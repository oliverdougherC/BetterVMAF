//
//  HeatMapView.swift
//  VMAF
//
//  Per-frame quality over time: a density heat map drawn in one pass, with
//  wheel/pinch zoom, drag pan, and a tooltip that names the exact frames.
//

import AppKit
import SwiftUI

/// Quality-over-time heat map.
///
/// The version it replaces asked Swift Charts for a `PointMark` per frame plus
/// ten gridline `RuleMark`s *inside the per-frame closure* (~15k marks for a
/// 1,439-frame clip, ~2.4M for two hours), animated all of them on every hover,
/// debounced the tooltip with a `Timer`, and put a label on every single second
/// of the timeline. It also coloured scores relative to the clip's own min/max
/// while labelling that scale "Poor…Excellent", so a 99.1 frame could be
/// painted red.
///
/// This one draws in a single `Canvas` pass at a viewport-sized level of detail
/// (`QualityTimeline`, built once per analysis), labels the time axis in clean
/// second/minute/hour strides, and keeps score → colour absolute: the same
/// score is the same colour in every comparison, even though the vertical
/// window defaults to the clip's own range so a narrow band stays readable.
struct HeatMapView: View {
    /// Precomputed for the whole result set by whoever ran the analysis.
    let timeline: QualityTimeline
    /// False for PDF export: no gestures, badges, or control row.
    var interactive: Bool = true

    @State private var viewport: HeatmapViewport
    @State private var scrollAccumulator: CGFloat = 0

    /// `viewport` is injectable so a caller (or a render test) can pin a zoom
    /// window instead of always starting at the whole clip.
    init(timeline: QualityTimeline, interactive: Bool = true, viewport: HeatmapViewport? = nil) {
        self.timeline = timeline
        self.interactive = interactive
        _viewport = State(initialValue: viewport ?? HeatmapViewport())
    }

    /// Height reserved under the plot: control row + legend when interactive,
    /// legend only for an exported still. The colour key stays in the PDF so a
    /// printed heat map is still readable.
    private var chromeHeight: CGFloat { interactive ? 52 : 24 }

    var body: some View {
        GeometryReader { proxy in
            let plot = ChartGeometry(size: CGSize(
                width: proxy.size.width,
                height: max(80, proxy.size.height - chromeHeight)
            ))
            let domain = viewport.displayDomain(in: timeline, geometry: plot)
            let scoreDomain = viewport.scoreDomain(in: timeline)
            let hover = hoverState(in: plot, domain: domain, scoreDomain: scoreDomain)

            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    HeatmapPlot(
                        timeline: timeline,
                        domain: domain,
                        scoreDomain: scoreDomain,
                        geometry: plot,
                        hover: hover
                    )

                    if interactive {
                        HeatmapOverview(timeline: timeline, viewport: viewport, domain: domain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                        if let hover {
                            HeatmapTooltip(timeline: timeline, hover: hover)
                                .frame(width: 216, alignment: .leading)
                                .position(tooltipOrigin(hover: hover, geometry: plot))
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: plot.size.height)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 1))
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): viewport.cursorLocation = location
                    case .ended: viewport.cursorLocation = nil
                    }
                }
                .gesture(interaction(plot: plot, domain: domain))
                .background(ScrollWheelReader { deltaY, deltaX, command in
                    readScroll(deltaY: deltaY, deltaX: deltaX, command: command, plot: plot)
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary(domain: domain))

                if interactive {
                    HeatmapControls(timeline: timeline, viewport: viewport, geometry: plot)
                }
                HeatmapLegend(scoreDomain: scoreDomain)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onDisappear { viewport.cursorLocation = nil }
    }

    // MARK: - Hover

    /// Derived from the cursor on every render, so no transform has to remember
    /// to clear it and a tooltip cannot describe a frame panned off screen.
    private func hoverState(in plot: ChartGeometry, domain: ClosedRange<TimeInterval>, scoreDomain: ClosedRange<Double>) -> Hover? {
        guard interactive, let location = viewport.cursorLocation, plot.data.contains(location) else { return nil }
        guard let index = timeline.nearestIndex(for: plot.time(atX: location.x, domain: domain)) else { return nil }
        return Hover(
            index: index,
            x: plot.x(for: timeline.time(at: index), domain: domain),
            y: plot.y(for: timeline.score(at: index), domain: scoreDomain),
            run: timeline.bandRun(containing: index),
            bucket: timeline.bucket(
                coveringIndex: index,
                columns: QualityTimeline.densityColumns(width: plot.dataWidth),
                domain: domain
            )
        )
    }

    struct Hover {
        var index: Int
        var x: CGFloat
        var y: CGFloat
        /// Frames at the hovered frame's band or worse, contiguous around it.
        var run: ClosedRange<Int>?
        /// The pixel column this frame was summarised into, if any.
        var bucket: QualityTimeline.Bucket?
    }

    private func tooltipOrigin(hover: Hover, geometry plot: ChartGeometry) -> CGPoint {
        let boxWidth: CGFloat = 216
        let boxHeight: CGFloat = 108
        let gap: CGFloat = 12
        let preferRight = hover.x + boxWidth / 2 + gap < plot.data.maxX
        let x = preferRight ? hover.x + boxWidth / 2 + gap : hover.x - boxWidth / 2 - gap
        return CGPoint(
            x: min(max(x, plot.data.minX + boxWidth / 2), plot.data.maxX - boxWidth / 2),
            y: min(max(hover.y, plot.data.minY + boxHeight / 2), plot.data.maxY - boxHeight / 2)
        )
    }

    // MARK: - Interaction

    /// Drag pans, pinch zooms about the window centre, double-click zooms 2× on
    /// the point clicked. Pointer tracking is `onContinuousHover`, so hover
    /// needs no gesture and no `Timer` debounce.
    private func interaction(plot: ChartGeometry, domain: ClosedRange<TimeInterval>) -> some Gesture {
        let drag = DragGesture(minimumDistance: 4)
            .onChanged { viewport.drag(byPixels: $0.translation.width, in: timeline, geometry: plot) }
            .onEnded { _ in viewport.endDrag() }

        let pinch = MagnificationGesture()
            .onChanged { viewport.pinch(to: $0, in: timeline, geometry: plot) }
            .onEnded { _ in viewport.endPinch() }

        let doubleClick = SpatialTapGesture(count: 2)
            .onEnded { value in
                viewport.cursorLocation = value.location
                viewport.zoom(by: 2, around: plot.time(atX: value.location.x, domain: domain), in: timeline, geometry: plot)
            }

        return drag
            .simultaneously(with: pinch)
            .simultaneously(with: doubleClick)
    }

    /// Plain wheel steps zoom at the cursor; ⌘-scroll or a horizontal delta pans.
    /// Returns false when the heat map had nothing to do with the event, leaving
    /// the page free to scroll.
    @discardableResult
    private func readScroll(deltaY: CGFloat, deltaX: CGFloat, command: Bool, plot: ChartGeometry) -> Bool {
        guard interactive, timeline.frameCount > 0 else { return false }

        if command || abs(deltaX) > abs(deltaY) + 0.5 {
            guard viewport.isZoomed else { return false }
            // A horizontal delta is the natural pan; ⌘ plus a vertical-only
            // wheel (a plain mouse) pans by that instead of doing nothing.
            let pixels = abs(deltaX) > abs(deltaY) + 0.5 ? deltaX : deltaY
            viewport.pan(byPixels: -pixels * 2, in: timeline, geometry: plot)
            return true
        }

        // A vertical wheel at full zoom-out would otherwise trap the page: only
        // steps that can change the window are consumed. Scroll up zooms in,
        // down zooms out.
        let limit = viewport.maximumZoom(in: timeline, geometry: plot)
        guard deltaY != 0, !(deltaY > 0 && viewport.zoom >= limit), !(deltaY < 0 && viewport.zoom <= 1) else {
            return false
        }

        // Accumulate so one notch is a visible but not violent step and
        // trackpad momentum cannot overshoot to the maximum zoom.
        scrollAccumulator += deltaY
        let steps = Int(scrollAccumulator / 3)
        guard steps != 0 else { return true }
        scrollAccumulator -= CGFloat(steps) * 3
        viewport.zoomAtCursor(by: pow(1.3, Double(steps)), in: timeline, geometry: plot)
        return true
    }

    private func accessibilitySummary(domain: ClosedRange<TimeInterval>) -> String {
        guard timeline.frameCount > 0 else { return "Quality heat map, no frame data" }
        let visible = timeline.slice(covering: domain).count
        let worst = timeline.worstIndex.map {
            String(format: ", worst frame %d at %.2f", timeline.frameNumber(at: $0), timeline.score(at: $0))
        } ?? ""
        return "Quality heat map, \(visible) of \(timeline.frameCount) frames in view, "
            + "\(TimeFormat.exact(domain.lowerBound)) to \(TimeFormat.exact(domain.upperBound))\(worst)."
    }
}

// MARK: - Plot

/// Axes and every data cell in one `Canvas` pass.
///
/// `Canvas` is immediate mode: the cost of a hover, pan, or zoom is one paint
/// of at most `columns × rows` rects, independent of how many frames the clip
/// contains.
private struct HeatmapPlot: View {
    let timeline: QualityTimeline
    let domain: ClosedRange<TimeInterval>
    let scoreDomain: ClosedRange<Double>
    let geometry: ChartGeometry
    let hover: HeatMapView.Hover?

    var body: some View {
        Canvas { context, size in
            render(context, size)
        }
        .accessibilityHidden(true)
    }

    private func render(_ context: GraphicsContext, _ size: CGSize) {
        let canvas = context
        canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .textBackgroundColor)))
        drawGrid(canvas)

        var data = canvas
        data.clip(to: Path(geometry.data))
        drawSeries(&data, plot: geometry.data)
        drawHover(&data)
        data.stroke(Path(geometry.data), with: .color(.secondary.opacity(0.25)), lineWidth: 1)

        drawLabels(canvas)
    }

    // MARK: grid

    private func drawGrid(_ context: GraphicsContext) {
        let plot = geometry.data

        for score in ScoreAxis.ticks(in: scoreDomain, height: plot.height).values {
            let y = geometry.y(for: score, domain: scoreDomain)
            context.stroke(horizontal(minX: plot.minX, maxX: plot.maxX, y: y),
                           with: .color(.secondary.opacity(0.15)), lineWidth: 1)
        }

        // Band edges: the score where the colour changes meaning, dashed in that
        // band's own colour so it reads as a threshold and not a gridline.
        for band in QualityBand.allCases.dropLast() where scoreDomain.contains(band.threshold) {
            let y = geometry.y(for: band.threshold, domain: scoreDomain)
            context.stroke(
                horizontal(minX: plot.minX, maxX: plot.maxX, y: y),
                with: .color(QualityScale.color(at: band.threshold).opacity(0.55)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }

        for tick in TimeAxis.ticks(in: domain, width: geometry.dataWidth).values {
            let x = geometry.x(for: tick, domain: domain)
            context.stroke(vertical(minY: plot.minY, maxY: plot.maxY, x: x),
                           with: .color(.secondary.opacity(0.1)), lineWidth: 1)
        }
    }

    // MARK: data

    private func drawSeries(_ context: inout GraphicsContext, plot: CGRect) {
        guard timeline.frameCount > 0 else { return }
        let columns = QualityTimeline.densityColumns(width: geometry.dataWidth)
        let framesPerPixel = timeline.framesPerColumn(width: geometry.dataWidth, domain: domain)
        // Exact frames are cheaper and truer than any summary; past that the
        // choice is between shading density cells and drawing an envelope.
        switch QualityTimeline.detailLevel(framesPerPixel: framesPerPixel) {
        case .exactFrames:
            drawExactFrames(&context, plot: plot)
        case .density:
            drawDensity(&context, plot: plot, columns: columns)
        case .envelope:
            drawEnvelope(&context, columns: columns, plot: plot)
        }
    }

    /// Occupied (time, score) cells, shaded by score with opacity carrying the
    /// count: many frames at one score read stronger than a lone frame passing
    /// through the bin.
    private func drawDensity(_ context: inout GraphicsContext, plot: CGRect, columns: Int) {
        let bins = ScoreAxis.binCount(height: plot.height)
        let grid = timeline.grid(columns: columns, bins: bins, domain: domain, scoreDomain: scoreDomain)
        guard !grid.cells.isEmpty else { return }

        let columnWidth = geometry.dataWidth / CGFloat(columns)
        let rowHeight = plot.height / CGFloat(grid.bins)
        // A lone frame reads as a narrow spike; where columns hold many frames
        // the cells touch, so dense regions read as one body.
        let gap = grid.maxCount > 1 ? 0.0 : max(0.5, columnWidth * 0.25)
        let total = Double(max(1, grid.maxCount))

        for cell in grid.cells {
            let rect = CGRect(
                x: plot.minX + CGFloat(cell.column) * columnWidth,
                y: plot.maxY - CGFloat(cell.bin + 1) * rowHeight,
                width: max(1, columnWidth - gap),
                height: max(1, rowHeight - gap)
            )
            let alpha = grid.maxCount == 1 ? 1.0 : min(1, 0.45 + 0.55 * sqrt(Double(cell.count) / total))
            context.fill(Path(rect), with: .color(QualityScale.color(at: grid.score(bin: cell.bin)).opacity(alpha)))
        }
    }

    /// Per-column worst-to-best span plus a mean line: what a two-hour clip
    /// looks like without drawing 216,000 marks. The span preserves every dip,
    /// the line preserves the trend, and the cost stays at two rects per column.
    private func drawEnvelope(_ context: inout GraphicsContext, columns: Int, plot: CGRect) {
        let buckets = timeline.buckets(count: columns, covering: domain)
        guard !buckets.isEmpty else { return }
        let columnWidth = geometry.dataWidth / CGFloat(columns)

        // Three layers per column: a soft wash over the min–max span coloured by
        // the mean (so the body of the encode reads as its real quality), a
        // saturated tick at the minimum (dips survive into the summary), and a
        // mean line on top for the trend. Connecting the minima as a polyline
        // would draw sawtooth noise, because each column's worst frame is a
        // different frame.
        for bucket in buckets {
            let x = geometry.x(for: bucket.startTime, domain: domain)
            let top = geometry.y(for: bucket.maxScore, domain: scoreDomain)
            let bottom = geometry.y(for: bucket.minScore, domain: scoreDomain)
            let width = max(1, columnWidth)

            context.fill(
                Path(CGRect(x: x, y: top, width: width, height: max(1, bottom - top))),
                with: .color(QualityScale.color(at: bucket.meanScore).opacity(0.22))
            )
            context.fill(
                Path(CGRect(x: x, y: bottom - 1.5, width: width, height: 1.5)),
                with: .color(QualityScale.color(at: bucket.minScore).opacity(0.95))
            )
        }

        let meanPath = Path { path in
            for (position, bucket) in buckets.enumerated() {
                let point = CGPoint(
                    x: geometry.x(for: bucket.startTime, domain: domain) + columnWidth / 2,
                    y: geometry.y(for: bucket.meanScore, domain: scoreDomain)
                )
                if position == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        // Light: at this level neighbouring columns can differ by a whole point,
        // and a heavy line through them reads as a solid mass instead of a trend.
        context.stroke(meanPath, with: .color(.primary.opacity(0.45)), lineWidth: 1)
    }

    /// One rect per frame, each extending to the next frame's position, so a
    /// zoomed-in view reads as a continuous band rather than scattered dots.
    private func drawExactFrames(_ context: inout GraphicsContext, plot: CGRect) {
        let range = timeline.slice(covering: domain)
        guard !range.isEmpty else { return }
        let height = max(4, min(8, plot.height / 40))
        let span = averageFrameSpan(in: range)
        // Start one frame before the window so a mark that begins off-screen
        // left still paints its visible sliver; the canvas clips the rest.
        let first = max(0, range.lowerBound - 1)
        let points: [CGPoint] = (first..<range.upperBound).map { index in
            CGPoint(
                x: geometry.x(for: timeline.time(at: index), domain: domain),
                y: geometry.y(for: timeline.score(at: index), domain: scoreDomain)
            )
        }
        let sampleSpacing = points.count > 1 ? abs(points[1].x - points[0].x) : 0

        // Once frames are clearly separated, a faint trace through them keeps
        // the shape of the clip readable; the marks stay the primary evidence.
        if sampleSpacing > 3, points.count > 1 {
            let trace = Path { path in
                path.addLines(points)
            }
            context.stroke(trace, with: .color(.primary.opacity(0.28)), lineWidth: 1)
        }

        let pixelsPerSecond = geometry.dataWidth / CGFloat(max(0.0001, domain.upperBound - domain.lowerBound))
        for (position, index) in (first..<range.upperBound).enumerated() {
            let score = timeline.score(at: index)
            let x = points[position].x
            let width = timeline.metrics.indices.contains(index + 1) && position + 1 < points.count
                ? max(2, points[position + 1].x - x)
                : max(2, CGFloat(span) * pixelsPerSecond)
            // Square-edged and contiguous: rounding each mark's ends would notch
            // between every pair and turn the band into scattered dots.
            context.fill(
                Path(CGRect(x: x, y: points[position].y - height / 2, width: width, height: height)),
                with: .color(QualityScale.color(at: score))
            )
        }
    }

    // MARK: hover

    private func drawHover(_ context: inout GraphicsContext) {
        guard let hover else { return }
        let plot = geometry.data
        let color = QualityScale.color(at: timeline.score(at: hover.index))

        // The run this frame belongs to — every neighbouring frame at the same
        // band or worse — so a colour is not mistaken for a single instant.
        if let run = hover.run, run.count > 1 {
            let startX = geometry.x(for: timeline.time(at: run.lowerBound), domain: domain)
            let endX = geometry.x(for: timeline.time(at: run.upperBound), domain: domain)
            let rect = CGRect(x: startX, y: plot.minY, width: max(2, endX - startX), height: plot.height)
            context.fill(Path(rect), with: .color(color.opacity(0.14)))
            context.fill(
                Path(roundedRect: CGRect(x: rect.minX, y: plot.minY, width: rect.width, height: 3), cornerRadius: 1.5),
                with: .color(color)
            )
        }

        context.stroke(vertical(minY: plot.minY, maxY: plot.maxY, x: hover.x),
                       with: .color(.primary.opacity(0.45)), lineWidth: 1)

        let marker = CGRect(x: hover.x - 5, y: hover.y - 5, width: 10, height: 10)
        context.stroke(Path(ellipseIn: marker), with: .color(.primary.opacity(0.85)), lineWidth: 1.5)
        context.fill(Path(ellipseIn: marker.insetBy(dx: 3, dy: 3)), with: .color(color))
    }

    // MARK: labels

    private func drawLabels(_ context: GraphicsContext) {
        let plot = geometry.data
        let scoreTicks = ScoreAxis.ticks(in: scoreDomain, height: plot.height)
        for score in scoreTicks.values {
            context.draw(
                Text(scoreTicks.label(score)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary),
                at: CGPoint(x: plot.minX - 5, y: geometry.y(for: score, domain: scoreDomain)),
                anchor: .trailing
            )
        }

        let timeTicks = TimeAxis.ticks(in: domain, width: geometry.dataWidth)
        for (position, tick) in timeTicks.values.enumerated() {
            let anchor: UnitPoint = position == 0 ? .leading
                : (position == timeTicks.values.count - 1 ? .trailing : .center)
            context.draw(
                Text(TimeFormat.string(tick, spacing: timeTicks.spacing))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary),
                at: CGPoint(x: geometry.x(for: tick, domain: domain), y: plot.maxY + 4),
                anchor: anchor
            )
        }
    }

    private func averageFrameSpan(in range: Range<Int>) -> TimeInterval {
        guard range.count > 1 else { return 1.0 / 30.0 }
        let first = timeline.time(at: range.lowerBound)
        let last = timeline.time(at: range.upperBound - 1)
        guard last > first else { return 1.0 / 30.0 }
        return (last - first) / Double(range.count - 1)
    }

    private func horizontal(minX: CGFloat, maxX: CGFloat, y: CGFloat) -> Path {
        Path {
            $0.move(to: CGPoint(x: minX, y: y))
            $0.addLine(to: CGPoint(x: maxX, y: y))
        }
    }

    private func vertical(minY: CGFloat, maxY: CGFloat, x: CGFloat) -> Path {
        Path {
            $0.move(to: CGPoint(x: x, y: minY))
            $0.addLine(to: CGPoint(x: x, y: maxY))
        }
    }
}

// MARK: - Tooltip

/// Names the exact frames a colour stands for, so a concern can be followed to
/// its interval instead of admired as a shape.
private struct HeatmapTooltip: View {
    let timeline: QualityTimeline
    let hover: HeatMapView.Hover

    var body: some View {
        // `hover.index` is always produced from this same timeline in the same
        // render, but a result swapping under a live cursor would trap on it.
        if timeline.metrics.indices.contains(hover.index) {
            content(for: timeline.metrics[hover.index])
        }
    }

    private func content(for metric: VMAFCalculator.FrameMetric) -> some View {
        let band = QualityBand(vmafScore: metric.vmafScore)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(band.tint).frame(width: 8, height: 8)
                Text(String(format: "%.2f", metric.vmafScore))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(band.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(TimeFormat.exact(metric.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Frame \(metric.frameNumber)")
            if let motion = metric.motionReading {
                Text("Motion (\(motion.feature)) \(String(format: "%.2f", motion.value))")
            }
            Text("ADM2 \(String(format: "%.3f", metric.integerAdm2))")

            if let run = hover.run, run.count > 1 {
                Divider()
                Text("\(band.rawValue) run: frames \(timeline.frameNumber(at: run.lowerBound))–\(timeline.frameNumber(at: run.upperBound)) · \(run.count) frames · \(TimeFormat.duration(timeline.time(at: run.upperBound) - timeline.time(at: run.lowerBound)))")
                    .foregroundStyle(band.tint)
            }

            if let bucket = hover.bucket, bucket.frameCount > 1 {
                Text("Column: \(bucket.frameCount) frames, \(String(format: "%.2f", bucket.minScore))–\(String(format: "%.2f", bucket.maxScore))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .multilineTextAlignment(.leading)
        .padding(7)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
    }
}

// MARK: - Overview

/// Miniature of the whole clip with the visible window marked, so panning has a
/// reference point. Only shown while zoomed.
private struct HeatmapOverview: View {
    let timeline: QualityTimeline
    let viewport: HeatmapViewport
    let domain: ClosedRange<TimeInterval>

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if viewport.isZoomed {
                Canvas { context, size in
                    draw(context, size)
                }
                .frame(width: 132, height: 12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.separator, lineWidth: 1))

                Text("wheel zoom · drag pan · double-click zoom here")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(2)
        .allowsHitTesting(false)
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize) {
        let full = timeline.timeRange
        let total = full.upperBound - full.lowerBound
        guard total > 0 else { return }

        // One rect per column spanning that column's min–max score, coloured by
        // its worst frame: the overview reads as a quality silhouette, so dips
        // are findable even when the window is a sliver of the clip.
        let columns = max(1, Int(size.width.rounded()))
        let buckets = timeline.buckets(count: columns, covering: full)
        guard !buckets.isEmpty else { return }

        let range = timeline.scoreRange
        let span = max(0.001, range.upperBound - range.lowerBound)
        func y(for score: Double) -> CGFloat {
            size.height * CGFloat(1 - (min(max(score, range.lowerBound), range.upperBound) - range.lowerBound) / span)
        }

        let columnWidth = size.width / CGFloat(columns)
        for bucket in buckets {
            let column = CGFloat((bucket.startTime - full.lowerBound) / total) * CGFloat(columns)
            let top = y(for: bucket.maxScore)
            let bottom = y(for: bucket.minScore)
            context.fill(
                Path(CGRect(x: column * columnWidth, y: top, width: max(1, columnWidth), height: max(1, bottom - top))),
                with: .color(QualityScale.color(at: bucket.minScore))
            )
        }

        guard domain.upperBound > domain.lowerBound else { return }
        let window = CGRect(
            x: size.width * CGFloat((domain.lowerBound - full.lowerBound) / total),
            y: 0,
            width: max(2, size.width * CGFloat((domain.upperBound - domain.lowerBound) / total)),
            height: size.height
        )
        context.fill(Path(window), with: .color(Color(nsColor: .textBackgroundColor).opacity(0.55)))
        context.stroke(Path(window), with: .color(.primary.opacity(0.8)), lineWidth: 1)
    }
}

// MARK: - Controls

private struct HeatmapControls: View {
    let timeline: QualityTimeline
    let viewport: HeatmapViewport
    let geometry: ChartGeometry

    var body: some View {
        HStack(spacing: 8) {
            Group {
                Button { viewport.stepZoom(increase: false, in: timeline, geometry: geometry) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(!viewport.isZoomed)
                .help("Zoom out")

                Button { viewport.stepZoom(increase: true, in: timeline, geometry: geometry) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom in")

                Button("Reset") { viewport.reset() }
                    .disabled(!viewport.isZoomed)
                    .help("Show the whole clip")
            }
            .controlSize(.small)

            Divider().frame(height: 14)

            // A segmented picker here renders as a squeezed, unusable control at
            // small sizes; a menu picker keeps the row honest at any width.
            Picker("Scale", selection: Bindable(viewport).verticalScale) {
                Text("Auto range").tag(HeatmapViewport.VerticalScale.autoFit)
                Text("Full 0–100").tag(HeatmapViewport.VerticalScale.full)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .controlSize(.small)
            .help("Auto range shows this clip's own score band so the difference between frames is visible; Full 0–100 shows the whole scale")

            if let worst = timeline.worstIndex {
                Button("Worst frame") {
                    viewport.focus(onIndex: worst, in: timeline, geometry: geometry)
                }
                .controlSize(.small)
                .help("Jump to frame \(timeline.frameNumber(at: worst)) at \(String(format: "%.2f", timeline.score(at: worst)))")
            }

            Spacer(minLength: 8)

            Text(status)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .font(.system(size: 11))
        .frame(height: 22)
    }

    private var status: String {
        let domain = viewport.displayDomain(in: timeline, geometry: geometry)
        let visible = timeline.slice(covering: domain).count
        guard viewport.isZoomed else {
            return "\(timeline.frameCount) frames · \(TimeFormat.duration(domain.upperBound - domain.lowerBound))"
        }
        // At a sub-second window, whole-second bounds print as "0:47 to 0:47";
        // let the label spacing follow the window size.
        let spacing = TimeAxis.spacing(width: geometry.dataWidth, span: domain.upperBound - domain.lowerBound)
        return String(
            format: "%d of %d frames · %@ to %@ · %.0f×",
            visible, timeline.frameCount,
            TimeFormat.string(domain.lowerBound, spacing: spacing),
            TimeFormat.string(domain.upperBound, spacing: spacing),
            viewport.zoom
        )
    }
}

/// Colour ramp with the numeric ranges each band means.
///
/// A colour alone invites reading it as a percentage of retained quality, and
/// the scale is absolute so the same score is the same colour in every
/// comparison; the printed ranges keep that honest.
private struct HeatmapLegend: View {
    let scoreDomain: ClosedRange<Double>

    var body: some View {
        let ticks = ScoreAxis.ticks(in: scoreDomain, height: 18)
        let span = max(0.0001, scoreDomain.upperBound - scoreDomain.lowerBound)

        HStack(spacing: 8) {
            Text("VMAF")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    LinearGradient(stops: QualityScale.legendStops(in: scoreDomain),
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 7)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.separator, lineWidth: 1))

                    ForEach(ticks.values, id: \.self) { score in
                        Text(ticks.label(score))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(
                                x: min(max(CGFloat((score - scoreDomain.lowerBound) / span) * proxy.size.width - 9, 0),
                                       max(0, proxy.size.width - 18)),
                                y: 8
                            )
                    }
                }
            }
            .frame(height: 18)
            .frame(maxWidth: 240)

            HStack(spacing: 7) {
                ForEach(QualityBand.allCases) { band in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1).fill(band.tint).frame(width: 5, height: 8)
                        Text("\(band.rawValue) \(band.rangeLabel)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fixedSize()
        }
        .frame(height: 18)
    }
}

// MARK: - Scroll wheel

/// Captures wheel events over the plot through two independent paths:
///
/// 1. an app-local event monitor, which sees every scroll event AppKit
///    dispatches to this app's window before responder routing — SwiftUI does
///    not reliably deliver `scrollWheel:` to a `background:` representable; and
/// 2. `scrollWheel:` on the placeholder view itself, in case the monitor is
///    unavailable (older system, or another consumer takes the event first).
///
/// Both paths consume an event only when the cursor is over the plot and the
/// heat map has something to do with it; everything else passes through so the
/// enclosing `ScrollView` keeps its momentum scrolling.
private struct ScrollWheelReader: NSViewRepresentable {
    /// Returns true when the heat map consumed the event.
    var onScroll: (_ deltaY: CGFloat, _ deltaX: CGFloat, _ command: Bool) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView(frame: .zero)
        view.setAccessibilityElement(false)
        context.coordinator.attach(view: view, onScroll: onScroll)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        var onScroll: (_ deltaY: CGFloat, _ deltaX: CGFloat, _ command: Bool) -> Bool = { _, _, _ in false }
        fileprivate weak var view: TrackingView?
        fileprivate var monitor: Any?

        func attach(view: TrackingView, onScroll: @escaping (_ deltaY: CGFloat, _ deltaX: CGFloat, _ command: Bool) -> Bool) {
            self.view = view
            self.onScroll = onScroll
            view.coordinator = self
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
        }

        /// True when this event was consumed for the heat map.
        fileprivate func handle(_ event: NSEvent) -> Bool {
            guard let view, let window = view.window, event.window == nil || event.window === window,
                  let location = cursorLocation(of: event, in: window) else { return false }
            let frameInWindow = view.convert(view.bounds, to: nil)
            guard frameInWindow.contains(location) else { return false }
            return onScroll(event.scrollingDeltaY, event.scrollingDeltaX,
                            event.modifierFlags.contains(.command))
        }

        /// Window-coordinate cursor position for a scroll event. Events AppKit
        /// dispatches to a window already carry it; untagged events (a direct
        /// `scrollWheel:` call, or synthesized ones) fall back to the live
        /// cursor so the over-the-plot test still means what it says.
        private func cursorLocation(of event: NSEvent, in window: NSWindow) -> NSPoint? {
            if event.window != nil { return event.locationInWindow }
            return window.convertPoint(fromScreen: NSEvent.mouseLocation)
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            self.monitor = nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    fileprivate final class TrackingView: NSView {
        weak var coordinator: Coordinator?

        override func scrollWheel(with event: NSEvent) {
            // The monitor normally consumes the event before it reaches here;
            // this is the fallback path when it did not.
            if coordinator?.handle(event) != true {
                super.scrollWheel(with: event)
            }
        }
    }
}
