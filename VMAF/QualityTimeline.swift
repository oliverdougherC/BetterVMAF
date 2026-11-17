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
        /// Index of the lowest-scoring frame in the column, so summaries can
        /// still name the exact frame (tooltip, accessibility).
        var worstIndex: Int
        /// Frames actually inside the column. A count, not `endIndex -
        /// startIndex`: with out-of-order timestamps the represented indices
        /// need not be contiguous.
        var frameCount: Int
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
    /// For each frame, the bounds of the longest span through it whose frames
    /// all sit in that frame's band or worse. Precomputed with a monotonic stack
    /// so hover is O(1): walking the run per pointer update is O(run length),
    /// which on a million-frame clip of consistent quality is the whole clip.
    private let runLeft: [Int]
    private let runRight: [Int]
    /// Smallest and largest score in the result and the index of the lowest,
    /// computed once instead of re-scanned per rendered mark.
    let scoreRange: ClosedRange<Double>
    let worstIndex: Int?
    /// Identity of the analysis these frames came from. Copies of a timeline
    /// share it; a freshly built result does not. Lets the view detect a
    /// swapped-in comparison and drop zoom state that belongs to the previous
    /// video instead of inheriting it.
    let analysisID = UUID()

    private let cache = Cache()

    init(metrics: [VMAFCalculator.FrameMetric]) {
        // libvmaf emits frames in presentation order. When it does not
        // (sampling, a decoder that reorders), sort first: the time axis, the
        // binary searches, and every aggregation below all assume it, and the
        // alternative — each mode silently disagreeing about which frames are
        // visible — shows a frame at one zoom and loses it at the next.
        var input = metrics
        if let first = input.first {
            var ordered = true
            var previous = first.timestamp
            for metric in input.dropFirst() {
                if metric.timestamp < previous { ordered = false; break }
                previous = metric.timestamp
            }
            if !ordered {
                input.sort { lhs, rhs in lhs.timestamp < rhs.timestamp }
            }
        }
        self.metrics = input

        var builtBands: [Int] = []
        builtBands.reserveCapacity(input.count)
        var minScore = Double.greatestFiniteMagnitude
        var maxScore = -Double.greatestFiniteMagnitude
        var worst: Int?

        for (index, metric) in input.enumerated() {
            let score = metric.vmafScore
            builtBands.append(QualityBand(vmafScore: score).caseIndex)
            if score < minScore {
                minScore = score
                worst = index
            }
            if score > maxScore { maxScore = score }
        }

        bandIndices = builtBands
        worstIndex = worst
        let runs = Self.bandRuns(for: builtBands)
        runLeft = runs.left
        runRight = runs.right

        if input.isEmpty {
            scoreRange = QualityScale.rampDomain
        } else if minScore == maxScore {
            // A constant-quality clip gets a padded domain instead of the
            // zero-width one that made the old color scale divide by zero.
            scoreRange = max(0, minScore - 1)...min(100, maxScore + 1)
        } else {
            scoreRange = minScore...maxScore
        }
    }

    /// For each index, the widest span around it whose bands are all at or
    /// below that index's band. The span ends at the nearest frame in each
    /// direction whose band is strictly *better*, so those boundaries are the
    /// previous/next-greater-element positions — found for every index in one
    /// linear pass with a monotonic stack, replacing a per-hover walk that was
    /// O(run length).
    private static func bandRuns(for bands: [Int]) -> (left: [Int], right: [Int]) {
        let count = bands.count
        var left = [Int](repeating: 0, count: count)
        var right = [Int](repeating: 0, count: count)
        var stack: [Int] = []

        for index in 0..<count {
            // Keep only frames strictly better than this one; the nearest such
            // frame is where a "this band or worse" run must stop.
            while let top = stack.last, bands[top] <= bands[index] { stack.removeLast() }
            left[index] = stack.last.map { $0 + 1 } ?? 0
            stack.append(index)
        }
        stack.removeAll(keepingCapacity: true)
        for index in stride(from: count - 1, through: 0, by: -1) {
            while let top = stack.last, bands[top] <= bands[index] { stack.removeLast() }
            right[index] = stack.last.map { $0 - 1 } ?? count - 1
            stack.append(index)
        }
        return (left, right)
    }

    // MARK: - Samples

    var frameCount: Int { metrics.count }

    func score(at index: Int) -> Double { metrics[index].vmafScore }
    func time(at index: Int) -> TimeInterval { metrics[index].timestamp }
    func frameNumber(at index: Int) -> Int { metrics[index].frameNumber }

    var timeRange: ClosedRange<TimeInterval> {
        guard let first = metrics.first, let last = metrics.last, last.timestamp > first.timestamp else {
            // Degenerate (empty, one frame, or repeated timestamps). Anchor on
            // the data rather than zero: with CA-04's negative first timestamp a
            // `0...1` fallback would exclude the only frame it has to show.
            let start = min(0, metrics.first?.timestamp ?? 0)
            return start...max(start + 1, metrics.last?.timestamp ?? 0)
        }
        return first.timestamp...last.timestamp
    }

    // MARK: - Index by time

    /// First sample index whose timestamp is >= `time`. `init` normalizes the
    /// sample order, so the binary search is always valid.
    func lowerBound(for time: TimeInterval) -> Int {
        var low = 0
        var high = metrics.count
        while low < high {
            let mid = low + (high - low) / 2
            if metrics[mid].timestamp < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Index of the sample nearest `time`, or nil when empty.
    func nearestIndex(for time: TimeInterval) -> Int? {
        guard !metrics.isEmpty else { return nil }
        let bound = lowerBound(for: time)
        if bound <= 0 { return 0 }
        if bound >= metrics.count { return metrics.count - 1 }
        return (time - metrics[bound - 1].timestamp <= metrics[bound].timestamp - time) ? bound - 1 : bound
    }

    /// The frame and summarized column a pointer at `(time, score)` names —
    /// the whole selection path the heat map hover and tooltip share, kept on
    /// the model so it is testable end to end.
    ///
    /// When the cursor is inside a column summarizing several frames, the
    /// cursor's score picks which of them it is pointing at (a spike's bad
    /// frame, not a neighbour at the same x); otherwise the time-nearest frame
    /// is the answer.
    func hoverTarget(atTime time: TimeInterval, score: Double, columns: Int, domain: ClosedRange<TimeInterval>) -> (index: Int, bucket: Bucket?)? {
        guard frameCount > 0 else { return nil }
        if let column = bucket(coveringTime: time, columns: columns, domain: domain), column.frameCount > 1 {
            return (nearestIndex(in: column, toScore: score), column)
        }
        guard let index = nearestIndex(for: time) else { return nil }
        return (index, nil)
    }

    /// The frame a pointer at `(time, score)` is pointing at, given the
    /// summarized column under it.
    ///
    /// Horizontal position alone is not enough once a column summarizes many
    /// frames: a bucket of 49 frames at 98 and one at 70 draws a spike, and
    /// time-only selection reports one of the 98s while the cursor sits on the
    /// 70 mark. Within the column the cursor's score picks the frame, so the
    /// tooltip names the marker it is actually on; at the bottom of the column
    /// that is `worstIndex`, the bad frame the dip was drawn for.
    func nearestIndex(in bucket: Bucket, toScore score: Double) -> Int {
        var best = bucket.worstIndex
        var bestDistance = Double.greatestFiniteMagnitude
        for index in bucket.startIndex..<max(bucket.startIndex + 1, bucket.endIndex) {
            let distance = abs(metrics[index].vmafScore - score)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// The widest span through `index` whose frames all sit in that frame's
    /// band or worse — the interval a quality concern should point at. Looked
    /// up from precomputed boundaries; see `bandRuns(for:)`.
    func bandRun(containing index: Int) -> ClosedRange<Int>? {
        guard bandIndices.indices.contains(index) else { return nil }
        // A frame already in the top band has no concern interval to escalate.
        guard bandIndices[index] < QualityBand.excellent.caseIndex else { return nil }
        return runLeft[index]...runRight[index]
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
    ///
    /// Each sample is placed by its own timestamp, exactly like `grid`, rather
    /// than by a scan cursor: with out-of-order frames (possible when sampling)
    /// a cursor silently files a frame under a column seconds away from its
    /// real time. Membership is therefore always the set of frames whose
    /// timestamp falls in the column, and `frameCount`/min/max/mean/worst are
    /// exact. `init` normalizes sample order, so `startIndex..<endIndex` is
    /// contiguous — `grid` and `slice` bin by the same timestamp arithmetic and
    /// all three modes see exactly the same frames.
    func buckets(count columns: Int, covering domain: ClosedRange<TimeInterval>) -> [Bucket] {
        guard !metrics.isEmpty, columns > 0 else { return [] }
        let columnCount = min(columns, max(1, metrics.count))
        let key = Key(columns: columnCount, bins: 1, domain: domain, scoreDomain: 0...0)
        if let cached = cache.buckets[key] { return cached }

        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return [] }

        // In-order data can be scanned from just the window, so a drag step
        // costs O(frames in view).
        let scan = slice(covering: domain)

        // Accumulate min/max/mean per column in one pass, no sorting.
        var minimum = [Double](repeating: .greatestFiniteMagnitude, count: columnCount)
        var maximum = [Double](repeating: -.greatestFiniteMagnitude, count: columnCount)
        var totals = [Double](repeating: 0, count: columnCount)
        var counts = [Int](repeating: 0, count: columnCount)
        var worst = [Int](repeating: -1, count: columnCount)
        var firstIndex = [Int](repeating: -1, count: columnCount)
        var lastIndex = [Int](repeating: -1, count: columnCount)

        for index in scan {
            let time = metrics[index].timestamp
            guard time >= domain.lowerBound else { continue }
            // The last column is half-open, but a sample sitting exactly on the
            // domain edge (always true for the final frame, since the range ends
            // at its timestamp) must land in it rather than nowhere.
            if time > domain.upperBound + span * 1e-9 { continue }
            let raw = Int((time - domain.lowerBound) / span * Double(columnCount))
            let column = min(max(raw, 0), columnCount - 1)

            let score = metrics[index].vmafScore
            if score < minimum[column] {
                minimum[column] = score
                worst[column] = index
            }
            if score > maximum[column] { maximum[column] = score }
            totals[column] += score
            if firstIndex[column] < 0 { firstIndex[column] = index }
            lastIndex[column] = index
            counts[column] += 1
        }

        var result: [Bucket] = []
        result.reserveCapacity(columnCount)
        for column in 0..<columnCount where counts[column] > 0 {
            result.append(Bucket(
                startTime: domain.lowerBound + span * Double(column) / Double(columnCount),
                endTime: domain.lowerBound + span * Double(column + 1) / Double(columnCount),
                startIndex: firstIndex[column],
                endIndex: lastIndex[column] + 1,
                minScore: minimum[column],
                maxScore: maximum[column],
                meanScore: totals[column] / Double(counts[column]),
                worstIndex: worst[column],
                frameCount: counts[column]
            ))
        }

        cache.buckets[key] = result
        cache.remember(key)
        return result
    }

    /// Bin the frames in `domain` into `columns` time slices by `bins` score
    /// rows.
    func grid(columns: Int, bins: Int, domain: ClosedRange<TimeInterval>, scoreDomain: ClosedRange<Double>) -> Grid {
        let empty = Grid(cells: [], bins: 0, scoreDomain: scoreDomain, maxCount: 0)
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

        let grid = Grid(cells: cells, bins: bins, scoreDomain: scoreDomain, maxCount: maxCount)
        cache.grids[key] = grid
        cache.remember(key)
        return grid
    }

    /// The column a timestamp belongs to, and the effective column count for a
    /// requested width. Shared by `buckets` and `bucket(coveringTime:)` so the
    /// tooltip and the drawing can never disagree about bucket membership.
    private func columnLayout(for time: TimeInterval, columns requested: Int, domain: ClosedRange<TimeInterval>)
        -> (columnCount: Int, column: Int)? {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, requested > 0 else { return nil }
        let columnCount = min(requested, max(1, metrics.count))
        guard time >= domain.lowerBound, time <= domain.upperBound + span * 1e-9 else { return nil }
        let column = min(max(Int((time - domain.lowerBound) / span * Double(columnCount)), 0), columnCount - 1)
        return (columnCount, column)
    }

    /// The bucket a timestamp falls into.
    func bucket(coveringTime time: TimeInterval, columns: Int, domain: ClosedRange<TimeInterval>) -> Bucket? {
        guard let layout = columnLayout(for: time, columns: columns, domain: domain) else { return nil }
        let built = buckets(count: layout.columnCount, covering: domain)
        let span = domain.upperBound - domain.lowerBound
        // The frame was counted into its own column's bucket by the same
        // arithmetic, so match that column's start directly.
        let target = domain.lowerBound + span * Double(layout.column) / Double(layout.columnCount)
        if let exact = built.first(where: { $0.startTime == target }) { return exact }
        return built.min { abs($0.startTime - target) < abs($1.startTime - target) }
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
        // Enough decimal places to render this stride exactly (0.5 → 1,
        // 0.25 → 2), then the digits after the whole second: 12.75 at a
        // quarter-second stride must not print as "0:12.8".
        let digits = decimalPlaces(for: spacing)
        let scale = pow(10.0, Double(digits))
        let fraction = Int((time * scale).rounded()) % Int(scale)
        guard fraction != 0 else { return clock }
        return String(format: "%@.%0\(digits)d", clock, fraction)
    }

    /// Smallest number of decimal places (1...3) that represents `spacing`
    /// exactly, so tick labels never round away from the gridline they name.
    private static func decimalPlaces(for spacing: TimeInterval) -> Int {
        for digits in 1...3 {
            let scaled = spacing * pow(10.0, Double(digits))
            if abs(scaled - scaled.rounded()) < 1e-9 { return digits }
        }
        return 3
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
