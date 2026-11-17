import Foundation

/// Owns the current FFmpeg child for a single comparison or batch. A batch
/// reuses its run for each item so cancellation also prevents the next launch.
final class ComparisonRun: @unchecked Sendable {
    let id = UUID()

    private let lock = NSLock()
    private let runningProcess = DispatchGroup()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func start(_ child: Process) throws {
        try lock.withLock {
            try checkCancellationLocked()
            precondition(process == nil)
            try child.run()
            process = child
            runningProcess.enter()
        }
    }

    func finish(_ child: Process) {
        lock.withLock {
            guard process === child else { return }
            process = nil
            runningProcess.leave()
        }
    }

    func isRunning(_ child: Process) -> Bool {
        lock.withLock { !cancelled && process === child }
    }

    func checkCancellation() throws {
        try lock.withLock { try checkCancellationLocked() }
    }

    private func checkCancellationLocked() throws {
        if cancelled { throw CancellationError() }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if let process, process.isRunning {
                // FFmpeg only writes a disposable log. Stop immediately so
                // quit can finish even if decoding or I/O has stalled.
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    func waitForExit() async {
        await withCheckedContinuation { continuation in
            runningProcess.notify(queue: .global()) { continuation.resume() }
        }
    }
}
