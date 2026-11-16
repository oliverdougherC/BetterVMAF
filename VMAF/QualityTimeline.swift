//
//  QualityTimeline.swift
//  VMAF
//
//  Level-of-detail model behind the heat map: at most one summary per plotted
//  pixel column instead of one SwiftUI mark per frame.
//

import Foundation

/// A frame timeline that can be reduced to viewport-sized detail.
///
/// The view used to ask Swift Charts for a `PointMark` per frame — plus ten
/// gridline `RuleMark`s *inside the per-frame closure* — so a 1,439-frame
/// comparison built ~15k marks, a two-hour clip ~2.4M, and every hover
/// re-filtered the visible array. This type keeps the raw metrics untouched for
/// metrics and export and gives the renderer either exact samples or one
/// density bucket per pixel column.
struct QualityTimeline {
    /// One pixel column's summary of the frames that fall inside it.
    struct Bucket {
        var startTime: TimeInterval
        var endTime: TimeInterval
        /// Index range into `metrics`, so a tooltip can still name frames.
        var startIndex: Int
        var endIndex: Int
        var minScore: Double
        var maxScore: Double
        var meanScore: Double
        /// Index of the lowest-scoring frame in the column: the evidence to surface.
        var worstIndex: Int

        var frameCount: Int { endIndex - startIndex }
    }

    /// One occupied (time column, score row) cell of the density grid.
    struct Cell {
        var column: Int
        var bin: Int
        var count: Int
    }

    /// Sparse occupancy of the score axis across a time window. Only occupied
    /// cells are stored, so drawing cost tracks frames in view, not
    /// `columns × rows`.
    struct Grid {
        var cells: [Cell]
        var columns: Int
        var bins: Int
        var scoreDomain: ClosedRange<Double>
        var maxCount: Int

        /// Score at the centre of a bin, for colouring.
        func score(bin: Int) -> Double {
            let span = scoreDomain.upperBound - scoreDomain.lowerBound
            return scoreDomain.lowerBound + span * (Double(bin) + 0.5) / Double(bins)
        }
    }

    let metrics: [VMAFCalculator.FrameMetric]
    /// `QualityBand.allCases` index per frame, precomputed for run detection.
    let bandIndices: [Int]
    /// Smallest and largest score in the result and the index of the lowest,
    /// computed once instead of re-scanned per rendered mark.
    let scoreRange: ClosedRange<Double>
    let worstIndex: Int?
    /// True when timestamps never decrease, which is what makes the binary
    /// searches below valid. A non-monotonic result scans linearly instead.
    let isTimeMonotonic: Bool

    private let cache = Cache()

    init(metrics: [VMAFCalculator.FrameMetric]) {
        self.metrics = metrics

        var builtBands: [Int] = []
        builtBands.reserveCapacity(metrics.count)
        var minScore = Double.greatestFiniteMagnitude
        var maxScore = -Double.greatestFiniteMagnitude
        var worst: Int?
        var monotonic = true
        var previousTime: TimeInterval?

        for (index, metric) in metrics.enumerated() {
            let score = metric.vmafScore
            builtBands.append(QualityBand(vmafScore: score).caseIndex)
            if let previousTime, metric.timestamp < previousTime { monotonic = false }
            previousTime = metric.timestamp
            if score < minScore {
                minScore = score
                worst = index
            }
            if score > maxScore { maxScore = score }
        }

        bandIndices = builtBands
        worstIndex = worst
        isTimeMonotonic = monotonic

        if metrics.isEmpty {
            scoreRange = QualityScale.rampDomain
        } else if minScore == maxScore {
            // A constant-quality clip gets a padded domain instead of the
            // zero-width one that made the old color scale divide by zero.
            scoreRange = max(0, minScore - 1)...min(100, maxScore + 1)
        } else {
            scoreRange = minScore...maxScore
        }
    }

    // MARK: - Samples

    var frameCount: Int { metrics.count }

    func score(at index: Int) -> Double { metrics[index].vmafScore }
    func time(at index: Int) -> TimeInterval { metrics[index].timestamp }
    func frameNumber(at index: Int) -> Int { metrics[index].frameNumber }

    var timeRange: ClosedRange<TimeInterval> {
        guard let first = metrics.first, let last = metrics.last, last.timestamp > first.timestamp else {
            return 0...max(1, metrics.last?.timestamp ?? 1)
        }
        return first.timestamp...last.timestamp
    }

    // MARK: - Index by time

    /// First sample index whose timestamp is >= `time`.
    func lowerBound(for time: TimeInterval) -> Int {
        guard isTimeMonotonic, !metrics.isEmpty else { return linearLowerBound(for: time) }
        var low = 0
        var high = metrics.count
        while low < high {
            let mid = low + (high - low) / 2
            if metrics[mid].timestamp < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func linearLowerBound(for time: TimeInterval) -> Int {
        for (index, metric) in metrics.enumerated() where metric.timestamp >= time { return index }
        return metrics.count
    }

    /// Index of the sample nearest `time`, or nil when empty.
    func nearestIndex(for time: TimeInterval) -> Int? {
        guard !metrics.isEmpty else { return nil }
        guard isTimeMonotonic else {
            var best = 0
            var bestDistance = TimeInterval.greatestFiniteMagnitude
            for index in metrics.indices {
                let distance = abs(metrics[index].timestamp - time)
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
            return best
        }
        let bound = lowerBound(for: time)
        if bound <= 0 { return 0 }
        if bound >= metrics.count { return metrics.count - 1 }
        return (time - metrics[bound - 1].timestamp <= metrics[bound].timestamp - time) ? bound - 1 : bound
    }

    /// Longest run through `index` whose frames all sit in that frame's band or
    /// *worse* — the interval a quality concern should point at. Bands are
    /// ordered poor → excellent, so worse means a lower index, and a frame
    /// already in the top band has no concern interval to escalate.
    func bandRun(containing index: Int) -> ClosedRange<Int>? {
        guard bandIndices.indices.contains(index) else { return nil }
        let band = bandIndices[index]
        guard band < (QualityBand.excellent.caseIndex) else { return nil }
        var start = index
        while start > 0, bandIndices[start - 1] <= band { start -= 1 }
        var end = index
        while end + 1 < bandIndices.count, bandIndices[end + 1] <= band { end += 1 }
        return start...end
    }

    // MARK: - Detail selection

    /// Exact samples inside `domain`, used when plotting each frame directly
    /// costs fewer marks than the bucketed grid.
    func slice(covering domain: ClosedRange<TimeInterval>) -> Range<Int> {
        guard !metrics.isEmpty else { return 0..<0 }
        let start = lowerBound(for: domain.lowerBound)
        let end = max(start, min(metrics.count, lowerBound(for: domain.upperBound) + 1))
        return start..<end
    }

    /// Average frames per pixel column in `domain`.
    func framesPerColumn(width: CGFloat, domain: ClosedRange<TimeInterval>) -> Double {
        let range = slice(covering: domain)
        guard width > 0, !range.isEmpty else { return 0 }
        return Double(range.count) / Double(width)
    }

    // MARK: - Level of detail

    /// How much detail a window can actually show.
    enum Detail: Equatable {
        /// One mark per frame: exact, and cheaper than any summary.
        case exactFrames
        /// Occupied (time, score) cells: the usual heat map.
        case density
        /// Per-column min/max wash, floor tick and mean line: past this point
        /// nearly every cell is occupied and shading is only stripe noise.
        case envelope
    }

    /// Frames per *pixel* above which density shading becomes noise: each
    /// two-pixel column then holds ~48 frames, so nearly every score bin is
    /// occupied and shading says nothing.
    static let envelopeFramesPerPixel = 24.0
    /// A density column is two pixels wide, so neighbouring columns average out
    /// instead of shimmering with per-pixel count differences.
    static let densityPixelWidth: CGFloat = 2

    /// `density` is frames per pixel.
    static func detailLevel(framesPerPixel density: Double) -> Detail {
        if density < 1.15 { return .exactFrames }
        if density > envelopeFramesPerPixel { return .envelope }
        return .density
    }

    static func densityColumns(width: CGFloat) -> Int {
        max(1, Int((width / densityPixelWidth).rounded()))
    }

    // MARK: - Aggregation

    /// One bucket per column covering `domain`. Hovering changes neither
    /// argument, so the work is paid once per zoom level and window size.
    func buckets(count columns: Int, covering domain: ClosedRange<TimeInterval>) -> [Bucket] {
        guard !metrics.isEmpty, columns > 0 else { return [] }
        let columnCount = min(columns, max(1, metrics.count))
        let key = Key(columns: columnCount, bins: 1, domain: domain, scoreDomain: 0...0)
        if let cached = cache.buckets[key] { return cached }

        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return [] }
        let first = lowerBound(for: domain.lowerBound)
        let last = min(metrics.count, lowerBound(for: domain.upperBound) + 1)
        guard first < last else { return [] }

        var result: [Bucket] = []
        result.reserveCapacity(min(columnCount, last - first))
        var index = first
        for column in 0..<columnCount {
            let columnStart = domain.lowerBound + span * Double(column) / Double(columnCount)
            var columnEnd = domain.lowerBound + span * Double(column + 1) / Double(columnCount)
            // The final column is half-open too, but a sample sitting exactly on
            // the domain edge (always true for the last frame, since the range
            // ends at its timestamp) must land in it rather than nowhere.
            if column == columnCount - 1 { columnEnd += span * 1e-9 }
            // Samples left of the column: a no-op after the first column, since
            // the inner loop already advanced past them.
            while index < last, metrics[index].timestamp < columnStart { index += 1 }
            guard index < last, metrics[index].timestamp < columnEnd else { continue }

            let startIndex = index
            var minScore = metrics[index].vmafScore
            var maxScore = minScore
            var total = 0.0
            var worst = index
            while index < last, metrics[index].timestamp < columnEnd {
                let score = metrics[index].vmafScore
                if score < minScore {
                    minScore = score
                    worst = index
                }
                if score > maxScore { maxScore = score }
                total += score
                index += 1
            }
            result.append(Bucket(
                startTime: columnStart,
                endTime: columnEnd,
                startIndex: startIndex,
                endIndex: index,
                minScore: minScore,
                maxScore: maxScore,
                meanScore: total / Double(index - startIndex),
                worstIndex: worst
            ))
        }

        cache.buckets[key] = result
        cache.remember(key)
        return result
    }

    /// Bin the frames in `domain` into `columns` time slices by `bins` score
    /// rows.
    func grid(columns: Int, bins: Int, domain: ClosedRange<TimeInterval>, scoreDomain: ClosedRange<Double>) -> Grid {
        let empty = Grid(cells: [], columns: 0, bins: 0, scoreDomain: scoreDomain, maxCount: 0)
        let range = slice(covering: domain)
        guard columns > 0, bins > 0, !range.isEmpty else { return empty }
        let key = Key(columns: columns, bins: bins, domain: domain, scoreDomain: scoreDomain)
        if let cached = cache.grids[key] { return cached }

        let span = domain.upperBound - domain.lowerBound
        let scoreSpan = scoreDomain.upperBound - scoreDomain.lowerBound
        guard span > 0, scoreSpan > 0 else { return empty }

        var counts = [Int](repeating: 0, count: columns * bins)
        for index in range {
            let time = metrics[index].timestamp
            guard time >= domain.lowerBound, time <= domain.upperBound else { continue }
            var column = Int((time - domain.lowerBound) / span * Double(columns))
            if column >= columns { column = columns - 1 }
            // Frames outside the plotted score window clamp to the edge row, so
            // a clipped range still shows them at the border.
            var bin = Int((metrics[index].vmafScore - scoreDomain.lowerBound) / scoreSpan * Double(bins))
            bin = min(max(bin, 0), bins - 1)
            counts[column * bins + bin] += 1
        }

        var cells: [Cell] = []
        cells.reserveCapacity(min(range.count, columns * bins))
        var maxCount = 0
        for column in 0..<columns {
            let offset = column * bins
            for bin in 0..<bins where counts[offset + bin] > 0 {
                let count = counts[offset + bin]
                if count > maxCount { maxCount = count }
                cells.append(Cell(column: column, bin: bin, count: count))
            }
        }

        let grid = Grid(cells: cells, columns: columns, bins: bins, scoreDomain: scoreDomain, maxCount: maxCount)
        cache.grids[key] = grid
        cache.remember(key)
        return grid
    }

    /// The bucket covering `index` at a given detail level, for the tooltip.
    func bucket(coveringIndex index: Int, columns: Int, domain: ClosedRange<TimeInterval>) -> Bucket? {
        guard metrics.indices.contains(index) else { return nil }
        let time = metrics[index].timestamp
        let found = buckets(count: columns, covering: domain)
        if let exact = found.first(where: { $0.startTime <= time && time < $0.endTime }) { return exact }
        // Rounding at the window edges can leave the last frame outside every
        // half-open column, so fall back to the bucket that holds its index.
        return found.first { $0.startIndex <= index && index < $0.endIndex }
    }

    // MARK: - Cache

    private struct Key: Hashable {
        var columns: Int
        var bins: Int
        var lower: TimeInterval
        var upper: TimeInterval
        var scoreLower: Double
        var scoreUpper: Double

        init(columns: Int, bins: Int, domain: ClosedRange<TimeInterval>, scoreDomain: ClosedRange<Double>) {
            self.columns = columns
            self.bins = bins
            lower = domain.lowerBound
            upper = domain.upperBound
            scoreLower = scoreDomain.lowerBound
            scoreUpper = scoreDomain.upperBound
        }
    }

    /// Reference type so copies of a timeline keep their aggregation, bounded so
    /// a long drag cannot retain one array per pixel step.
    private final class Cache {
        private static let limit = 24

        var buckets: [Key: [Bucket]] = [:]
        var grids: [Key: Grid] = [:]
        private var order: [Key] = []

        func remember(_ key: Key) {
            order.removeAll { $0 == key }
            order.append(key)
            while order.count > Self.limit {
                let stale = order.removeFirst()
                buckets[stale] = nil
                grids[stale] = nil
            }
        }
    }
}

/// Score-axis ticks and labels.
///
/// A VMAF score is 0...100 with no implied distribution, so ticks are always
/// round numbers at a stride that fits, and the same formatter labels the axis
/// and the legend so they cannot disagree.
enum ScoreAxis {
    struct Ticks {
        var values: [Double]
        var spacing: Double

        func label(_ score: Double) -> String {
            spacing >= 1 ? String(format: "%.0f", score) : String(format: spacing >= 0.2 ? "%.1f" : "%.2f", score)
        }
    }

    private static let strides: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 25]
    /// Points a score label needs vertically.
    static let labelSpacing: CGFloat = 22

    static func ticks(in domain: ClosedRange<Double>, height: CGFloat) -> Ticks {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, height > 0 else { return Ticks(values: [], spacing: 1) }
        let maxLabels = max(2, Int(height / labelSpacing))
        let spacing = strides.first(where: { $0 >= span / Double(maxLabels) }) ?? strides.last!
        return Ticks(values: aligned(from: domain, spacing: spacing), spacing: spacing)
    }

    /// Rows in the density grid: one per ~3pt. Enough to separate 0.1-VMAF
    /// differences without drawing a million cells.
    static func binCount(height: CGFloat) -> Int {
        max(24, min(400, Int(height / 3)))
    }

    private static func aligned(from domain: ClosedRange<Double>, spacing: Double) -> [Double] {
        guard spacing > 0 else { return [] }
        var values: [Double] = []
        var value = ceil(domain.lowerBound / spacing) * spacing
        let capacity = Int((domain.upperBound - domain.lowerBound) / spacing) + 2
        while value <= domain.upperBound + spacing * 0.0001, values.count < capacity {
            values.append((value * 1000).rounded() / 1000)
            value += spacing
        }
        return values
    }
}

/// Time-axis ticks at clean second/minute/hour strides.
///
/// The axis used `AxisMarks(values: .stride(by: 1))`, so a 46-minute clip asked
/// for 2,786 one-second labels and SwiftUI drew them all overlapping — the
/// clutter in the screenshot. This picks the coarsest clean stride that keeps
/// labels `labelSpacing` apart.
enum TimeAxis {
    struct Ticks {
        var values: [TimeInterval]
        var spacing: TimeInterval
    }

    static let labelSpacing: CGFloat = 74

    private static let strides: [TimeInterval] = [
        0.1, 0.2, 0.25, 0.5,
        1, 2, 5, 10, 15, 30,
        60, 120, 300, 600, 900, 1800,
        3600, 7200, 10_800, 14_400, 21_600, 43_200,
    ]

    static func spacing(width: CGFloat, span: TimeInterval) -> TimeInterval {
        guard width > 0, span > 0 else { return strides.last! }
        let maxLabels = max(2, Int(width / labelSpacing))
        return strides.first(where: { $0 >= span / Double(maxLabels) }) ?? strides.last!
    }

    static func ticks(in domain: ClosedRange<TimeInterval>, width: CGFloat) -> Ticks {
        let spacing = spacing(width: width, span: domain.upperBound - domain.lowerBound)
        guard spacing > 0, domain.upperBound > domain.lowerBound else { return Ticks(values: [], spacing: 1) }
        var values: [TimeInterval] = []
        var value = ceil(domain.lowerBound / spacing) * spacing
        let capacity = Int((domain.upperBound - domain.lowerBound) / spacing) + 2
        while value <= domain.upperBound + spacing * 0.0001, values.count < capacity {
            // Snap away from float dust so 59.99999999 never prints as 0:59.
            values.append((value * 1000).rounded() / 1000)
            value += spacing
        }
        return Ticks(values: values, spacing: spacing)
    }
}

enum TimeFormat {
    /// `m:ss`, or `h:mm:ss` once the stride reaches an hour. Below a second the
    /// label carries the fraction (`0:23.7`), where whole-second labels would
    /// repeat or vanish.
    static func string(_ time: TimeInterval, spacing: TimeInterval = 1) -> String {
        let seconds = Int(time) % 60
        let minutes = (Int(time) / 60) % 60
        let hours = Int(time) / 3600
        let clock = hours > 0 || spacing >= 3600
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
        guard spacing < 1 else { return clock }
        // Decimal places the stride needs (0.5 → 1, 0.25 → 2), then the digits
        // after the whole second: 21.5 at a half-second stride is "0:21.5".
        let digits = min(3, Int(max(1, (-log10(spacing)).rounded())))
        let scale = pow(10.0, Double(digits))
        let fraction = Int((time * scale).rounded()) % Int(scale)
        guard fraction != 0 else { return clock }
        return String(format: "%@.%0\(digits)d", clock, fraction)
    }

    /// A span, not a position: `0.77s` reads where `0:00` would look like the
    /// start of the clip.
    static func duration(_ span: TimeInterval) -> String {
        if span < 1 { return String(format: "%.2fs", span) }
        if span < 60 { return String(format: "%.1fs", span) }
        return string(span, spacing: 1)
    }

    /// Millisecond precision, for pointing at one frame. The app's first-frame
    /// timestamp can be slightly negative (CA-04), which is formatted as
    /// `-0:00.033` rather than a borrow from the second before zero.
    static func exact(_ time: TimeInterval) -> String {
        let whole = Int(time.magnitude)
        let millis = min(999, Int(((time.magnitude - Double(whole)) * 1000).rounded()))
        let seconds = whole % 60
        let minutes = (whole / 60) % 60
        let hours = whole / 3600
        let sign = time < 0 ? "-" : ""
        if hours > 0 {
            return String(format: "%@%d:%02d:%02d.%03d", sign, hours, minutes, seconds, millis)
        }
        return String(format: "%@%d:%02d.%03d", sign, minutes, seconds, millis)
    }
}
