import Foundation

final class CancelClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    func set() { lock.lock(); value = DispatchTime.now().uptimeNanoseconds; lock.unlock() }
    func elapsed() -> Double { lock.lock(); defer {lock.unlock()}; return Double(DispatchTime.now().uptimeNanoseconds-value)/1e9 }
}

@main struct Benchmark {
    static func main() async throws {
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let record=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        let trials=record["trials"] as! [[String:Any]]
        var results:[[String:Any]]=[]
        for trial in trials.prefix(2) {
            var argv=trial["argv"] as! [String]
            let executable=argv.removeFirst()
            let runner=OwnedProcess()
            let clock=CancelClock()
            let cancellation=Task {
                try await Task.sleep(for:.seconds(1))
                clock.set()
                runner.cancel()
            }
            var cancellationError=false
            do { _ = try await runner.run(executable:URL(fileURLWithPath:executable),arguments:argv) }
            catch is CancellationError { cancellationError=true }
            catch { throw error }
            _ = try await cancellation.value
            let elapsed=clock.elapsed()
            precondition(cancellationError)
            results.append(["threads":trial["threads"]!,"cancel_to_owner_return_seconds":elapsed,"observed_cancellation_error":cancellationError,"termination_grace_seconds":0.75,"note":"Actual OwnedProcess implementation; return waits for child exit and pipe drains. One trial per worker count, no UI involvement."])
        }
        let output=try JSONSerialization.data(withJSONObject:["results":results],options:[.prettyPrinted,.sortedKeys])
        print(String(data:output,encoding:.utf8)!)
    }
}
