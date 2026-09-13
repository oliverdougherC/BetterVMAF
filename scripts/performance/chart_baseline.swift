import Foundation

// Reproduce baseline summaries/hover work (78f6631), not Swift Charts rendering.
// Full quadratic heatmap intentionally not rendered: count operations exactly,
// measure 32 real per-point min/max scans, report extrapolation separately.
struct Point { let timestamp: Double; let score: Double }
@inline(never) func extent(_ points: [Point]) -> Double {
    (points.max { $0.score < $1.score }?.score ?? 0) - (points.min { $0.score < $1.score }?.score ?? 0)
}
@inline(never) func hover(_ points: [Point], _ target: Double) -> Double {
    points.map { ($0.timestamp, abs($0.timestamp-target)) }.min { $0.1 < $1.1 }!.0
}
var rows: [[String: Any]] = []
var sink = 0.0
for count in [216_000, 1_000_000] {
    let begin = Date.timeIntervalSinceReferenceDate
    let points = (0..<count).map { Point(timestamp: Double($0)/30, score: $0 == count/2 ? 1 : 85+sin(Double($0)*0.01)*10) }
    let allocated = Date.timeIntervalSinceReferenceDate-begin
    let summaryStart = Date.timeIntervalSinceReferenceDate
    for _ in 0..<32 { sink += extent(points) }
    let perScan = (Date.timeIntervalSinceReferenceDate-summaryStart)/32
    let hoverStart = Date.timeIntervalSinceReferenceDate
    for index in 0..<32 { sink += hover(points, Double(index)*Double(count)/32/30) }
    let perHover = (Date.timeIntervalSinceReferenceDate-hoverStart)/32
    rows.append(["raw_points":count, "main_chart_marks":count*12,"heatmap_marks":count*11,"combined_marks":count*23,
                 "point_storage_bytes":count*MemoryLayout<Point>.stride,"construction_seconds":allocated,
                 "measured_per_point_min_max_seconds":perScan,"measured_linear_hover_seconds":perHover,
                 "extrapolated_heatmap_min_max_seconds":perScan*Double(count),
                 "note":"Release-optimized Foundation microbenchmark on main thread; mark counts static; full chart was not rendered; extrapolation is not observed UI time."])
}
let result:[String:Any] = ["baseline_commit":"78f6631605132d0ea75cf92869e65231968d46fb", "rows":rows,"optimizer_sink":sink]
let data=try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
print(String(data:data,encoding:.utf8)!)
