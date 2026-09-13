import Foundation
import Darwin

@main struct Benchmark {
    static func main() throws {
        var rows: [[String: Any]] = []
        var sink = 0.0
        for count in [216_000, 1_000_000] {
            let points: [TimelinePoint] = (0..<count).map { index in
                var value = 85.0+sin(Double(index)*0.01)*10.0
                if index == 12345 { value = -17.0 }
                if index == 12346 { value = 111.0 }
                return TimelinePoint(id:index,time:Double(index)/30.0,value:value)
            }
            let range = 0...points.last!.time
            var durations: [Double] = []
            var envelope: [TimelinePoint] = []
            for _ in 0..<31 {
                let start = DispatchTime.now().uptimeNanoseconds
                envelope = TimelineData.envelope(points,range:range,buckets:500)
                durations.append(Double(DispatchTime.now().uptimeNanoseconds-start)/1e9)
                sink += envelope.reduce(0) { $0+$1.value }
            }
            durations.sort()
            let start = DispatchTime.now().uptimeNanoseconds
            for index in 0..<100_000 { sink += TimelineData.nearest(points,time:Double(index % count)/30+0.009)!.value }
            let hover = Double(DispatchTime.now().uptimeNanoseconds-start)/1e9/100_000
            var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
            precondition(envelope.count<=1002)
            precondition(envelope.contains{$0.id==12345} && envelope.contains{$0.id==12346})
            rows.append(["raw_points":count,"bucket_count":500,"plotted_points":envelope.count,"maximum_points":1002,
                         "envelope_median_seconds":durations[15],"envelope_p95_seconds":durations[29],"nearest_mean_seconds":hover,
                         "peak_process_rss_bytes":usage.ru_maxrss,"raw_point_storage_bytes":count*MemoryLayout<TimelinePoint>.stride,
                         "both_adjacent_opposite_spikes_retained":true,"note":"Optimized actual TimelineData implementation; no SwiftUI rendering or frame-pacing claim. RSS cumulative process peak."])
        }
        let data=try JSONSerialization.data(withJSONObject:["rows":rows,"optimizer_sink":sink],options:[.prettyPrinted,.sortedKeys])
        print(String(data:data,encoding:.utf8)!)
    }
}
