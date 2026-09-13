import Foundation
import Testing
@testable import VMAF

struct AnalysisCoreTests {
    @Test func progressSurvivesEveryByteBoundary() throws {
        let raw = Data("frame=100001\r\nfps=0.0\nout_time_us=1250000\nprogress=continue\nframe=100002\nfps=40.2\nprogress=end\n".utf8)
        for split in 0...raw.count {
            var parser = AnalysisProgressParser()
            let updates = parser.append(Data(raw.prefix(split)), totalFrames: 200002) + parser.append(Data(raw.dropFirst(split)), totalFrames: 200002)
            #expect(updates.count == 2)
            #expect(updates.first?.frameCount == 100001)
            #expect(updates.first?.elapsedMediaSeconds == 1.25)
            #expect(updates.first?.fraction == 0.5)
            #expect(updates.last?.isFinished == true)
        }
        var parser = AnalysisProgressParser()
        #expect(parser.append(raw, totalFrames: nil).first?.fraction == nil)
    }

    @Test func exceptionalMetricsAndOptionalFeaturesRoundtrip() throws {
        let json = Data(#"{"version":"test","fps":999,"frames":[{"frameNum":0,"metrics":{"vmaf":-2.5,"aux":null,"future":7.1}}],"pooled_metrics":{"vmaf":{"mean":-2.5}},"aggregate_metrics":{"numeric":3.5,"infinite":"inf"}}"#.utf8)
        let log = try MetricLog.decode(json)
        #expect(log.frames[0].metrics["aux"] == .undefined)
        #expect(log.frames[0].metrics["future"] == .finite(7.1))
        #expect(log.aggregateMetrics["numeric"] == .finite(3.5))
        #expect(log.frames[0].metrics["vmaf"] == .finite(-2.5))
        #expect(try LegacyMetricImport(data: json).provenanceStatus == "legacy-unknown")
        let values: [MetricValue] = [.positiveInfinity, .negativeInfinity, .undefined, .unavailable, .finite(-90)]
        #expect(try JSONDecoder().decode([MetricValue].self, from: JSONEncoder().encode(values)) == values)
        #expect(throws: (any Error).self) { try MetricLog.decode(Data(#"{"frames":[],"pooled_metrics":{}}"#.utf8)) }
        #expect(throws: (any Error).self) { try MetricLog.decode(Data(#"{"frames":[{"frameNum":0,"metrics":{"aux":8}}]}"#.utf8)) }
        #expect(throws: (any Error).self) { try MetricLog.decode(Data("{\"frames\":[".utf8)) }
    }

    @Test func authoritativeCadenceAndVFR() throws {
        for (count, fps) in [(240, 24), (600, 60)] {
            let stream = Self.stream(timeBase: "1/\(fps)", fps: "\(fps)/1")
            let frames = (0..<count).map { DecodedFrame(pts: Int64($0), time: Double($0) / Double(fps), duration: 1 / Double(fps), interlaced: false) }
            let video = ProbedVideo(stream: stream, frames: frames)
            let pairs = try AnalysisCorrespondence.validate(reference: video, comparison: video)
            #expect(pairs.first?.timestamp == 0)
            #expect(abs(pairs.reduce(0) { $0 + $1.duration } - 10) < 0.000001)
            #expect(pairs.last!.timestamp < 10)
        }
        let raw = Data("best_effort_timestamp=0|duration=1001|interlaced_frame=0\nbest_effort_timestamp=1001|duration=2002|interlaced_frame=0\nbest_effort_timestamp=3003|duration=1001|interlaced_frame=0\n".utf8)
        let frames = try AnalysisProbe.decodeFrames(raw, timeBase: "1/24000")
        #expect(abs(frames[1].duration - 2002.0 / 24000) < 1e-12)
        #expect(abs(frames[2].time - 3003.0 / 24000) < 1e-12)
        #expect(throws: (any Error).self) { try AnalysisProbe.decodeFrames(Data("best_effort_timestamp=0\n".utf8), timeBase: "1/24") }
    }

    @Test func mismatchedTimingAndContentAreRefused() throws {
        let frames = (0..<5).map { DecodedFrame(pts: Int64($0), time: Double($0) / 24, duration: 1.0 / 24, interlaced: false) }
        let source = ProbedVideo(stream: Self.stream(), frames: frames)
        let shorter = ProbedVideo(stream: Self.stream(), frames: Array(frames.dropLast()))
        #expect(throws: (any Error).self) { try AnalysisCorrespondence.validate(reference: source, comparison: shorter) }
        #expect(throws: (any Error).self) { try AnalysisCorrespondence.validate(reference: shorter, comparison: source) }
        let shifted = ProbedVideo(stream: Self.stream(), frames: frames.map { .init(pts: $0.pts + 1, time: $0.time + 1.0 / 24, duration: $0.duration, interlaced: false) })
        #expect(throws: (any Error).self) { try AnalysisCorrespondence.validate(reference: source, comparison: shifted) }
        let signatures = Data((0..<5).flatMap { Array(repeating: UInt8($0 * 20), count: 256) })
        let shift = Data((0..<5).flatMap { Array(repeating: UInt8(min(4, $0 + 1) * 20), count: 256) })
        #expect(try AnalysisCorrespondence.validateSignatures(reference: signatures, comparison: signatures, frameCount: 5).count == 2)
        #expect(throws: (any Error).self) { try AnalysisCorrespondence.validateSignatures(reference: signatures, comparison: shift, frameCount: 5) }
    }

    @Test func xpsnrRetainsNativePoolingAndInfinity() throws {
        let stats = "n: 1 XPSNR y: 20 XPSNR u: inf XPSNR v: 40\nn: 2 XPSNR y: 40 XPSNR u: inf XPSNR v: 40\n"
        let log = try XPSNRLog.parse(stats: stats, stderr: "[Parsed_xpsnr_0] XPSNR  y: 22.9671  u: inf  v: 40.0000 (minimum: 22.9671)", expectedCount: 2)
        #expect(log.minimumPlaneAverage == .finite(22.9671))
        #expect(log.planeAverages["xpsnr_u"] == .positiveInfinity)
        #expect(log.frames[1]["xpsnr_y"] == .finite(40))
        #expect(throws: (any Error).self) { try XPSNRLog.parse(stats: stats, stderr: "", expectedCount: 2) }
        let graph = AnalysisService.filterGraph(reference: Self.stream(), comparison: Self.stream(), configuration: .init())
        #expect(graph.contains("[rx][dx]xpsnr="))
        #expect(graph.contains("[dv][rv]libvmaf="))
        #expect(graph.contains("repeatlast=0:eof_action=endall"))
        #expect(!graph.contains("99"))
    }

    @Test func identitiesDetectSameSizeChanges() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("first".utf8).write(to: url)
        let a = try AnalysisFileIdentity.capture(url)
        try Data("other".utf8).write(to: url)
        let b = try AnalysisFileIdentity.capture(url)
        #expect(a.byteCount == b.byteCount)
        #expect(a.sha256 != b.sha256)
    }

    @Test func colorGeometryAndMultipleStreamBoundariesAreExplicit() throws {
        let frames = [DecodedFrame(pts: 0, time: 0, duration: 1.0 / 24, interlaced: false)]
        func altered(_ key: String, _ value: Any) throws -> ProbedVideo {
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.stream())) as? [String: Any])
            object[key] = value
            return ProbedVideo(stream: try JSONDecoder().decode(AnalysisStream.self, from: JSONSerialization.data(withJSONObject: object)), frames: frames)
        }
        for transfer in ["smpte2084", "arib-std-b67", "unknown"] {
            #expect(throws: (any Error).self) { try AnalysisCorrespondence.validateStream(altered("colorTransfer", transfer)) }
        }
        for (key, value) in [("rotation", 90 as Any), ("sampleAspectRatio", "4:3" as Any), ("pixelFormat", "yuv444p" as Any)] {
            #expect(throws: (any Error).self) { try AnalysisCorrespondence.validateStream(altered(key, value)) }
        }
        try AnalysisCorrespondence.validateStream(altered("colorRange", "pc"))
        let two = Data(#"{"streams":[{"width":640,"height":360},{"width":640,"height":360}]}"#.utf8)
        #expect(throws: (any Error).self) { try AnalysisProbe.decodeStream(two) }
        let artwork = Data(#"{"streams":[{"width":640,"height":360,"disposition":{"attached_pic":1}}]}"#.utf8)
        #expect(throws: (any Error).self) { try AnalysisProbe.decodeStream(artwork) }
    }

    @Test func containerQuantizationIsMatchedWithoutAcceptingAFrameShift() throws {
        let sourceFrames = (0..<24).map { DecodedFrame(pts: Int64($0 * 1000), time: Double($0) / 24, duration: 1.0 / 24, interlaced: false) }
        let encodeFrames = (0..<24).map { index in
            let pts = Int64((Double(index) * 1000 / 24).rounded())
            let next = Int64((Double(index + 1) * 1000 / 24).rounded())
            return DecodedFrame(pts: pts, time: Double(pts) / 1000, duration: Double(next - pts) / 1000, interlaced: false)
        }
        let source = ProbedVideo(stream: Self.stream(timeBase: "1/24000"), frames: sourceFrames)
        let encode = ProbedVideo(stream: Self.stream(timeBase: "1/1000"), frames: encodeFrames)
        let pairs = try AnalysisCorrespondence.validate(reference: source, comparison: encode)
        #expect(pairs.count == 24)
        #expect(pairs[1].referenceTimestamp != pairs[1].comparisonTimestamp)
        #expect(AnalysisService.filterGraph(reference: source.stream, comparison: encode.stream, configuration: .init()).contains("ts_sync_mode=nearest"))
    }

    static func stream(timeBase: String = "1/24", fps: String = "24/1") -> AnalysisStream {
        AnalysisStream(index: 0, codec: "ffv1", width: 640, height: 360, pixelFormat: "yuv420p10le", bitDepth: 10,
            timeBase: timeBase, averageFrameRate: fps, sampleAspectRatio: "1:1", rotation: 0, fieldOrder: "progressive",
            colorMatrix: "bt709", colorPrimaries: "bt709", colorTransfer: "bt709", colorRange: "tv", chromaLocation: "left", duration: 10)
    }
}
