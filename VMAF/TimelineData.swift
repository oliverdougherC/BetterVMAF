import Foundation

struct TimelinePoint: Identifiable, Sendable, Equatable {
    let id: Int
    let time: Double
    let value: Double
}

/// Sorted immutable samples. Only visualization is reduced; callers retain raw data.
enum TimelineData {
    static func lowerBound(_ points: [TimelinePoint], time: Double) -> Int {
        var low = 0
        var high = points.count
        while low < high {
            let mid = low + (high - low) / 2
            if points[mid].time < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    static func nearest(_ points: [TimelinePoint], time: Double) -> TimelinePoint? {
        guard !points.isEmpty, time.isFinite else { return nil }
        let i = lowerBound(points, time: time)
        if i == 0 { return points[0] }
        if i == points.count { return points[i - 1] }
        return time - points[i - 1].time <= points[i].time - time ? points[i - 1] : points[i]
    }

    /// Each time bucket keeps both extrema in their original order, plus endpoints.
    /// At most 2*buckets+2 samples, independent of movie duration.
    static func envelope(_ points: [TimelinePoint], range: ClosedRange<Double>, buckets: Int) -> [TimelinePoint] {
        guard !points.isEmpty, buckets > 0 else { return [] }
        let start = lowerBound(points, time: range.lowerBound)
        var end = lowerBound(points, time: range.upperBound)
        if end < points.count, points[end].time == range.upperBound { end += 1 }
        guard start < end else { return [] }
        if end - start <= 2 * buckets + 2 { return Array(points[start..<end]) }
        let span = max(range.upperBound - range.lowerBound, Double.ulpOfOne)
        var output: [TimelinePoint] = [points[start]]
        output.reserveCapacity(2 * buckets + 2)
        var bucketID = -1
        var minIndex = start
        var maxIndex = start
        func appendExtrema() {
            for index in [min(minIndex, maxIndex), max(minIndex, maxIndex)] {
                if output.last?.id != points[index].id { output.append(points[index]) }
            }
        }
        for i in start..<end {
            let bucket = min(buckets - 1, Int((points[i].time - range.lowerBound) / span * Double(buckets)))
            if bucket != bucketID {
                if bucketID >= 0 { appendExtrema() }
                bucketID = bucket
                minIndex = i
                maxIndex = i
            } else {
                if points[i].value < points[minIndex].value { minIndex = i }
                if points[i].value > points[maxIndex].value { maxIndex = i }
            }
        }
        appendExtrema()
        if output.last?.id != points[end - 1].id { output.append(points[end - 1]) }
        return output
    }

    static func domain(_ points: [TimelinePoint]) -> ClosedRange<Double> {
        var minimum = Double.infinity
        var maximum = -Double.infinity
        for point in points where point.value.isFinite {
            minimum = min(minimum, point.value)
            maximum = max(maximum, point.value)
        }
        guard minimum.isFinite, maximum.isFinite else { return 0...1 }
        let padding = max(1, (maximum - minimum) * 0.05)
        return (minimum - padding)...(maximum + padding)
    }
}
