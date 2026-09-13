import Foundation
import Darwin

struct ProcessOutput: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: String
}

/// One child at a time. Cancellation does not complete until waitUntilExit and both pipe drains finish.
final class OwnedProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var child: Process?
    private var cancelled = false
    private let terminationGrace: TimeInterval

    init(terminationGrace: TimeInterval = 0.75) { self.terminationGrace = terminationGrace }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = child
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
        guard let process else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + terminationGrace) { [weak self, weak process] in
            guard let self, let process else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            if self.child === process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func run(executable: URL, arguments: [String], directory: URL? = nil,
             stdoutLimit: Int = 256 * 1024 * 1024,
             onStdout: (@Sendable (Data) -> Void)? = nil) async throws -> ProcessOutput {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try self.execute(executable: executable, arguments: arguments,
                            directory: directory, stdoutLimit: stdoutLimit, onStdout: onStdout))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.cancel() }
    }

    private func execute(executable: URL, arguments: [String], directory: URL?, stdoutLimit: Int,
                         onStdout: (@Sendable (Data) -> Void)?) throws -> ProcessOutput {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AnalysisError.engine("Missing or non-executable engine: \(executable.lastPathComponent). Reinstall BetterVMAF.")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // No shell, environment search path, or Homebrew dynamic-library fallback.
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("DYLD_") { environment.removeValue(forKey: key) }
        process.environment = environment
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice
        defer {
            try? out.fileHandleForReading.close(); try? out.fileHandleForWriting.close()
            try? err.fileHandleForReading.close(); try? err.fileHandleForWriting.close()
            lock.lock(); if child === process { child = nil }; lock.unlock()
        }
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        if child != nil { lock.unlock(); throw AnalysisError.invalid("An analysis process is already running.") }
        child = process
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        // Dedicated drains prevent either pipe filling while the owner waits for the child.
        let stdout = DrainBuffer(limit: stdoutLimit, keepTail: false)
        let stderr = DrainBuffer(limit: 128 * 1024, keepTail: true)
        let drains = DispatchGroup()
        for (pipe, buffer, callback) in [(out, stdout, onStdout), (err, stderr, nil)] {
            drains.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { drains.leave() }
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    let alreadyOverflowed = buffer.overflow
                    buffer.append(data)
                    if buffer.overflow && !alreadyOverflowed { self.cancel() }
                    callback?(data)
                }
            }
        }
        process.waitUntilExit()
        drains.wait()
        lock.lock(); let wasCancelled = cancelled; lock.unlock()
        if stdout.overflow { throw AnalysisError.invalid("Engine output exceeded its supported \(stdoutLimit) byte budget; the child was stopped.") }
        if wasCancelled { throw CancellationError() }
        return ProcessOutput(status: process.terminationStatus, stdout: stdout.data,
                             stderr: String(decoding: stderr.data, as: UTF8.self))
    }
}

private final class DrainBuffer: @unchecked Sendable {
    var data = Data()
    var overflow = false
    let limit: Int
    let keepTail: Bool
    init(limit: Int, keepTail: Bool) { self.limit = limit; self.keepTail = keepTail }
    func append(_ bytes: Data) {
        if keepTail {
            data.append(bytes)
            if data.count > limit { data.removeFirst(data.count - limit) }
        } else {
            let remaining = max(0, limit - data.count)
            data.append(bytes.prefix(remaining))
            if bytes.count > remaining { overflow = true }
        }
    }
}

struct AnalysisProgress: Sendable, Equatable {
    let frameCount: Int
    let processingFPS: Double
    let elapsedMediaSeconds: Double?
    let totalFrames: Int?
    let isFinished: Bool
    var fraction: Double? {
        guard let totalFrames, totalFrames > 0 else { return nil }
        return min(1, max(0, Double(frameCount) / Double(totalFrames)))
    }
}

/// UTF-8 and records may split at any byte; only progress=continue/end commits a record.
struct AnalysisProgressParser {
    private var bytes = Data()
    private var fields: [String: String] = [:]
    mutating func append(_ data: Data, totalFrames: Int?) -> [AnalysisProgress] {
        bytes.append(data)
        var output: [AnalysisProgress] = []
        while let newline = bytes.firstIndex(of: 10) {
            let line = String(decoding: bytes[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            bytes.removeSubrange(...newline)
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]), value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
            if key == "progress" {
                output.append(AnalysisProgress(frameCount: Int(fields["frame"] ?? "") ?? 0,
                    processingFPS: Double(fields["fps"] ?? "") ?? 0,
                    elapsedMediaSeconds: Double(fields["out_time_us"] ?? "").map { $0 / 1_000_000 },
                    totalFrames: totalFrames, isFinished: value == "end"))
                fields.removeAll(keepingCapacity: true)
            }
        }
        // Machine records are tiny; malformed unbounded lines cannot consume movie-sized RAM.
        if bytes.count > 65536 { bytes.removeAll() }
        return output
    }
}
