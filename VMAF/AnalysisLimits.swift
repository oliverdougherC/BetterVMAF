import Foundation

/// Explicit current support budget, independent of the much larger synthetic chart datasets.
enum AnalysisLimits {
    static let maximumFrames = 500_000
    static let maximumMetricLogBytes: Int64 = 512 * 1024 * 1024
    static let frameLimitMessage = "This comparison exceeds the current 500,000 decoded-frame support budget. Compare a shorter matching segment; no partial quality verdict was produced."
    static let logLimitMessage = "Metric logs exceeded the current 512 MB support budget. The engine was stopped and no partial quality verdict was produced. Compare a shorter matching segment."
}

/// Bounds disk growth while a child runs, then checks again before allocating/parsing its log.
final class AnalysisLogBudget: @unchecked Sendable {
    private let timer: DispatchSourceTimer
    private let lock = NSLock()
    private var violation = false
    private let files: [URL]
    private let limit: Int64
    private let onExceeded: @Sendable () -> Void
    var exceeded: Bool { lock.lock(); defer { lock.unlock() }; return violation }
    init(files: [URL], limit: Int64 = AnalysisLimits.maximumMetricLogBytes, onExceeded: @escaping @Sendable () -> Void) {
        self.files = files; self.limit = limit; self.onExceeded = onExceeded
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
    }
    func check() {
        let total = files.reduce(Int64(0)) { value, file in
            value + ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
        guard total > limit else { return }
        lock.lock(); let first = !violation; violation = true; lock.unlock()
        if first { onExceeded() }
    }
    func stop() { timer.cancel() }
    deinit { timer.cancel() }
}
