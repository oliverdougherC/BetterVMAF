import Foundation
import Darwin
import Testing
@testable import VMAF

struct AnalysisProcessTests {
    @Test func realProcessDrainsBothPipesAndLaunchFailureIsTyped() async throws {
        let runner = OwnedProcess()
        let result = try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'complete stdout'; printf 'complete stderr' >&2"])
        #expect(result.status == 0)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "complete stdout")
        #expect(result.stderr == "complete stderr")
        await #expect(throws: (any Error).self) {
            try await runner.run(executable: URL(fileURLWithPath: "/nonexistent/bettervmaf-engine"), arguments: [])
        }
    }

    @Test func cancellationEscalatesAndReapsOwnedPID() async throws {
        let runner = OwnedProcess(terminationGrace: 0.15)
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        let task = Task {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; echo $$; exec /bin/sleep 30"], onStdout: { continuation.yield($0) })
        }
        var iterator = stream.makeAsyncIterator()
        let ready = try #require(await iterator.next())
        let pid = try #require(Int32(String(decoding: ready, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        let start = Date()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
        continuation.finish()
    }

    @Test func concurrentRejectedRunCannotEraseFirstChildOwnership() async throws {
        let runner = OwnedProcess(terminationGrace: 0.15)
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        let first = Task {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; echo $$; exec /bin/sleep 30"], onStdout: { continuation.yield($0) })
        }
        var iterator = stream.makeAsyncIterator()
        let ready = try #require(await iterator.next())
        let pid = try #require(Int32(String(decoding: ready, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        await #expect(throws: (any Error).self) { try await runner.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["second"]) }
        runner.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(kill(pid, 0) == -1)
        continuation.finish()
    }

    @Test func cancelBeforeLaunchDoesNotStartProcess() async throws {
        let runner = OwnedProcess()
        runner.cancel()
        await #expect(throws: CancellationError.self) { try await runner.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["must not run"]) }
    }

    @Test func stdoutAndDiskBudgetsStopBeforeParsingUnboundedOutput() async throws {
        let runner = OwnedProcess(terminationGrace: 0.1)
        await #expect(throws: (any Error).self) {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "while :; do printf '01234567890123456789'; done"], stdoutLimit: 100)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 1, count: 101).write(to: url)
        let budget = AnalysisLogBudget(files: [url], limit: 100, onExceeded: {})
        budget.check()
        #expect(budget.exceeded)
        budget.stop()
    }

    @Test func bundledStandardIdentityAndSchemaRoundtrip() async throws {
        let engine = try AnalysisEngine.bundled()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BetterVMAF fixture ' :;,[]$() \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source café ' :;,[]$().mkv")
        let generated = try await OwnedProcess().run(executable: engine.ffmpeg, arguments: ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=24:duration=0.5",
            "-vf", "format=yuv420p10le,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709", "-c:v", "ffv1",
            "-color_range", "tv", "-colorspace", "bt709", "-color_trc", "bt709", "-color_primaries", "bt709", "-chroma_sample_location", "left", input.path])
        #expect(generated.status == 0)
        let calculator = VMAFCalculator(engine: engine)
        let result = try await calculator.calculateVMAF(referenceVideo: input, comparisonVideo: input)
        #expect(result.frameCount == 12)
        #expect(result.frameMetrics.first?.timestamp == 0)
        #expect(result.score.isFinite)
        let analysis = try #require(result.analysis)
        #expect(analysis.reference.sha256 == analysis.comparison.sha256)
        #expect(analysis.aggregateMetrics["xpsnr_min_plane"] == .positiveInfinity)
        #expect(analysis.samples.allSatisfy { $0.values["cambi_full_reference"] == .finite(0) })
        #expect(result.frameMetrics.allSatisfy { $0.integerVifScales.allSatisfy { $0 == nil } })
        let roundtrip = try JSONDecoder().decode(AnalysisResult.self, from: JSONEncoder().encode(analysis))
        #expect(roundtrip.samples.count == analysis.samples.count)
        #expect(roundtrip.reference == analysis.reference)
        #expect(roundtrip.configuration == analysis.configuration)
        #expect(roundtrip.modelSHA256 == analysis.modelSHA256)
        let shifted = directory.appendingPathComponent("same-count-shift.mkv")
        let shiftedOutput = try await OwnedProcess().run(executable: engine.ffmpeg, arguments: ["-v", "error", "-i", input.path,
            "-vf", "trim=start_frame=1,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=0.041667,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709",
            "-fps_mode", "passthrough", "-c:v", "ffv1", "-chroma_sample_location", "left", shifted.path])
        #expect(shiftedOutput.status == 0)
        let shiftedProbe = try await AnalysisProbe(executable: engine.ffprobe, runner: OwnedProcess()).read(shifted)
        #expect(shiftedProbe.frames.count == result.frameCount)
        await #expect(throws: (any Error).self) { try await calculator.calculateVMAF(referenceVideo: input, comparisonVideo: shifted) }
        // Malformed imported primaries must produce a typed failure, never a force-unwrap crash.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(analysis)) as? [String: Any])
        var samples = try #require(object["samples"] as? [[String: Any]])
        var values = try #require(samples[0]["values"] as? [String: Any])
        values.removeValue(forKey: "vmaf"); samples[0]["values"] = values; object["samples"] = samples
        await #expect(throws: (any Error).self) {
            try await calculator.calculateVMAF(referenceVideo: directory.appendingPathComponent("missing.mov"), comparisonVideo: input)
        }
        #expect(calculator.getLastCommand().isEmpty)
        #expect(calculator.getLastTerminationStatus() == nil)
        let malformed = try JSONDecoder().decode(AnalysisResult.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: (any Error).self) { try VMAFCalculator.VMAFResult(analysis: malformed) }
    }
}
