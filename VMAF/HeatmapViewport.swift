//
//  HeatmapViewport.swift
//  VMAF
//
//  The heat map's zoom window, cursor tracking, and plot coordinate maths.
//

import AppKit
import Observation
import SwiftUI

/// Zoom window over a `QualityTimeline`.
///
/// Pan is stored as a fraction of the pannable remainder at the current zoom
/// rather than an absolute time, so zoom and drag cannot drift the window past
/// either end of the clip, the same window survives a resize, and the
/// timeline's aggregation caches keep hitting. Hover is *derived* from
/// `cursorLocation` by the view, so a zoom or pan can never leave a stale
/// tooltip behind and no transform has to remember to clear one.
@Observable
@MainActor
final class HeatmapViewport {
    /// 1 shows the whole clip.
    private(set) var zoom: Double = 1
    /// 0...1 across the pannable remainder at the current zoom.
    private(set) var offset: Double = 0

    /// Vertical axis choice. Auto-fit is the default because a VMAF result
    /// usually lives in a narrow band near the top — on a 93.75–100 clip a
    /// fixed 0–100 axis spends 94% of the plot showing nothing, which is why
    /// the old graph read as a flat smear. The scale stays absolute: scores on
    /// the axis and colours in `QualityScale` are the same numbers in every
    /// comparison, only the visible window changes.
    enum VerticalScale: Equatable {
        /// Fit the clip's own range, with a little headroom.
        case autoFit
        /// The whole 0–100 range.
        case full
    }

    var verticalScale: VerticalScale = .autoFit {
        didSet { if oldValue != verticalScale { cursorLocation = nil } }
    }

    /// Pointer inside the plot, in plot coordinates; nil when outside.
    var cursorLocation: CGPoint?
    private var dragStart: (offset: Double, zoom: Double)?
    private var pinchStart: (offset: Double, zoom: Double)?

    /// Zoom past which a pixel column is narrower than one frame: more zoom
    /// shows no new information. Capped so a degenerate width cannot hang.
    static let absoluteMaxZoom: Double = 50_000

    var isZoomed: Bool { zoom > 1.0001 }

    // MARK: - Domains

    func displayDomain(in timeline: QualityTimeline, geometry: ChartGeometry) -> ClosedRange<TimeInterval> {
        let full = timeline.timeRange
        let total = full.upperBound - full.lowerBound
        guard total > 0, timeline.frameCount > 0 else { return full }
        let zoom = clampedZoom(in: timeline, geometry: geometry)
        let visible = total / zoom
        let pannable = total - visible
        guard pannable > 0 else { return full }
        let start = full.lowerBound + pannable * min(max(offset, 0), 1)
        return start...(start + visible)
    }

    func scoreDomain(in timeline: QualityTimeline) -> ClosedRange<Double> {
        guard timeline.frameCount > 0 else { return QualityScale.rampDomain }
        guard verticalScale == .autoFit else { return 0...100 }
        let range = timeline.scoreRange
        // Pad by ~8% of the span, never less than half a point, so a spike is
        // not flush against the axis and a one-point range stays readable. The
        // top keeps its pad even past 100: a frame at a perfect 100 still needs
        // room for its mark, and the axis simply stops labelling at 100.
        let pad = max(0.5, (range.upperBound - range.lowerBound) * 0.08)
        return max(0, range.lowerBound - pad)...(range.upperBound + pad)
    }

    /// How many samples the finest zoom window still holds. Past that the
    /// frames are already wider than the pointer needs, and more zoom shows the
    /// same frames, just fatter.
    static let minSamplesAtMaxZoom = 20.0

    func maximumZoom(in timeline: QualityTimeline, geometry: ChartGeometry) -> Double {
        guard geometry.dataWidth > 0, timeline.frameCount > 1 else { return 1 }
        let total = timeline.timeRange.upperBound - timeline.timeRange.lowerBound
        guard total > 0 else { return 1 }
        // Sampling can space the frames further apart than one frame duration,
        // so work from the mean sample interval rather than the frame count.
        let meanInterval = total / Double(timeline.frameCount - 1)
        return max(2, min(Self.absoluteMaxZoom, total / (meanInterval * Self.minSamplesAtMaxZoom)))
    }

    private func clampedZoom(in timeline: QualityTimeline, geometry: ChartGeometry) -> Double {
        min(max(zoom, 1), maximumZoom(in: timeline, geometry: geometry))
    }

    // MARK: - Transforms

    /// Zoom by `factor`, holding the moment at `time` in the same place on screen.
    func zoom(by factor: Double, around time: TimeInterval, in timeline: QualityTimeline, geometry: ChartGeometry) {
        rescale(to: zoom * factor, keeping: time, in: timeline, geometry: geometry)
    }

    /// Multiply the current scale by `factor`, anchored at the cursor.
    func zoomAtCursor(by factor: Double, in timeline: QualityTimeline, geometry: ChartGeometry) {
        let domain = displayDomain(in: timeline, geometry: geometry)
        let anchor = cursorLocation.map { geometry.time(atX: $0.x, domain: domain) }
            ?? (domain.lowerBound + domain.upperBound) / 2
        rescale(to: zoom * factor, keeping: anchor, in: timeline, geometry: geometry)
    }

    /// Absolute zoom setter. The gestures use relative transforms (`zoom(by:)`,
    /// `pinch(to:)`); this is the seam for tests and any caller that needs to
    /// pin a window (e.g. restoring a saved inspection range).
    func setZoom(_ value: Double, in timeline: QualityTimeline, geometry: ChartGeometry) {
        let domain = displayDomain(in: timeline, geometry: geometry)
        rescale(to: value, keeping: (domain.lowerBound + domain.upperBound) / 2, in: timeline, geometry: geometry)
    }

    /// Button zoom snaps to powers of two and anchors on the cursor, so
    /// repeated clicks land on predictable scales.
    func stepZoom(increase: Bool, in timeline: QualityTimeline, geometry: ChartGeometry) {
        let domain = displayDomain(in: timeline, geometry: geometry)
        let anchor = cursorLocation.map { geometry.time(atX: $0.x, domain: domain) }
            ?? (domain.lowerBound + domain.upperBound) / 2
        let base = clampedZoom(in: timeline, geometry: geometry)
        let target = increase ? pow(2, floor(log2(base)) + 1) : pow(2, ceil(log2(base)) - 1)
        rescale(to: max(1, target), keeping: anchor, in: timeline, geometry: geometry)
    }

    private func rescale(to requested: Double, keeping time: TimeInterval, in timeline: QualityTimeline, geometry: ChartGeometry) {
        let full = timeline.timeRange
        let total = full.upperBound - full.lowerBound
        guard total > 0 else { return }
        let limit = maximumZoom(in: timeline, geometry: geometry)
        let oldZoom = min(max(zoom, 1), limit)
        let newZoom = min(max(requested, 1), limit)
        guard newZoom != oldZoom else { zoom = newZoom; return }

        let oldVisible = total / oldZoom
        let visible = total / newZoom
        let windowStart = full.lowerBound + (total - oldVisible) * min(max(offset, 0), 1)
        let fraction = oldVisible > 0 ? (time - windowStart) / oldVisible : 0.5
        let newStart = time - min(max(fraction, 0), 1) * visible
        zoom = newZoom
        offset = normalized(newStart - full.lowerBound, visible: visible, total: total)
    }

    func pan(byPixels pixels: CGFloat, in timeline: QualityTimeline, geometry: ChartGeometry) {
        let full = timeline.timeRange
        let total = full.upperBound - full.lowerBound
        guard total > 0, geometry.dataWidth > 0 else { return }
        let visible = total / clampedZoom(in: timeline, geometry: geometry)
        let pannable = total - visible
        guard pannable > 0 else { return }
        offset = min(max(offset + Double(pixels / geometry.dataWidth) * (visible / pannable), 0), 1)
    }

    /// Drag tracking: `translation` is the distance from where the drag began,
    /// so the window sticks under the cursor instead of accumulating.
    func drag(byPixels translation: CGFloat, in timeline: QualityTimeline, geometry: ChartGeometry) {
        if dragStart == nil { dragStart = (offset, zoom) }
        guard let start = dragStart else { return }
        let full = timeline.timeRange
        let total = full.upperBound - full.lowerBound
        let visible = total / max(start.zoom, 1)
        let pannable = total - visible
        guard total > 0, geometry.dataWidth > 0, pannable > 0 else { return }
        zoom = start.zoom
        offset = min(max(start.offset - Double(translation / geometry.dataWidth) * (visible / pannable), 0), 1)
    }

    func endDrag() { dragStart = nil }

    func pinch(to scale: Double, in timeline: QualityTimeline, geometry: ChartGeometry) {
        if pinchStart == nil { pinchStart = (offset, zoom) }
        guard let start = pinchStart else { return }
        let domain = displayDomain(in: timeline, geometry: geometry)
        zoom = start.zoom
        offset = start.offset
        rescale(to: start.zoom * scale, keeping: (domain.lowerBound + domain.upperBound) / 2, in: timeline, geometry: geometry)
    }

    func endPinch() { pinchStart = nil }

    /// Centre the window on a frame, zooming in far enough to make it findable.
    func focus(onIndex index: Int, in timeline: QualityTimeline, geometry: ChartGeometry) {
        let full = timeline.timeRange
        let total = full.upperBound - full.lowerBound
        guard total > 0, timeline.metrics.indices.contains(index) else { return }
        let target = timeline.metrics[index].timestamp
        // Show the frame inside ~1/40th of the visible span, or the current
        // zoom if that is already finer.
        let desiredVisible = min(total / max(zoom, 1), total / 40)
        zoom = min(max(total / max(desiredVisible, total / Self.absoluteMaxZoom), 1), maximumZoom(in: timeline, geometry: geometry))
        let visible = total / zoom
        offset = normalized(target - full.lowerBound - visible / 2, visible: visible, total: total)
    }

    func reset() {
        zoom = 1
        offset = 0
        dragStart = nil
        pinchStart = nil
    }

    private func normalized(_ startDelta: TimeInterval, visible: TimeInterval, total: TimeInterval) -> Double {
        let pannable = total - visible
        guard pannable > 0 else { return 0 }
        return min(max(Double(startDelta / pannable), 0), 1)
    }
}

/// Plot rectangle and the two coordinate conversions.
///
/// Insets are fixed numbers rather than measured label widths so that drawing a
/// label can never change the plot rect and set off a resize feedback loop.
struct ChartGeometry: Equatable {
    static let leading: CGFloat = 36
    static let trailing: CGFloat = 10
    static let top: CGFloat = 10
    static let bottom: CGFloat = 18

    var size: CGSize

    var data: CGRect {
        CGRect(
            x: Self.leading,
            y: Self.top,
            width: max(1, size.width - Self.leading - Self.trailing),
            height: max(1, size.height - Self.top - Self.bottom)
        )
    }

    var dataWidth: CGFloat { data.width }

    func x(for time: TimeInterval, domain: ClosedRange<TimeInterval>) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return data.midX }
        return data.minX + CGFloat((time - domain.lowerBound) / span) * data.width
    }

    func time(atX x: CGFloat, domain: ClosedRange<TimeInterval>) -> TimeInterval {
        let span = domain.upperBound - domain.lowerBound
        let fraction = Double(max(0, min(1, (x - data.minX) / max(1, data.width))))
        return domain.lowerBound + span * fraction
    }

    func y(for score: Double, domain: ClosedRange<Double>) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return data.midY }
        return data.maxY - CGFloat(max(-0.02, min(1.02, (score - domain.lowerBound) / span))) * data.height
    }
}
