import Foundation
import AVFoundation
import CoreVideo
import Testing
@testable import VMAF

@MainActor
struct WorkflowPlaybackTests {
    @Test func nativePlayerSeeksBothExactVFRFramePairs() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("playback-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let times = [0.0, 1.0 / 24, 3.0 / 24]
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64, AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 1]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for (index, time) in times.enumerated() {
            var pixel: CVPixelBuffer?
            #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess)
            let buffer = try #require(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(40 + index * 70), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            for _ in 0..<200 { if input.isReadyForMoreMediaData { break }; try await Task.sleep(for: .milliseconds(5)) }
            #expect(adaptor.append(buffer, withPresentationTime: CMTime(value: [0, 1, 3][index], timescale: 24)))
        }
        writer.endSession(atSourceTime: CMTime(value: 4, timescale: 24))
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        let file = try AnalysisFileIdentity.capture(url)
        let template = ExportFixture.analysis()
        let samples = template.samples.map { sample in
            let p = sample.pair
            let timestamp = times[p.index]
            let pts: Int64 = [0, 1, 3][p.index]
            return AnalysisMetricSample(pair: AnalysisFramePair(index: p.index, referencePTS: pts, comparisonPTS: pts, referenceTimeBase: "1/24", comparisonTimeBase: "1/24", referenceTimestamp: timestamp, comparisonTimestamp: timestamp, timestamp: timestamp, duration: p.index == 1 ? 2.0 / 24 : 1.0 / 24), values: sample.values)
        }
        let analysis = AnalysisResult(schemaVersion: 1, runID: UUID(), createdAt: Date(), reference: file, comparison: file, referenceStream: template.referenceStream, comparisonStream: template.comparisonStream, configuration: template.configuration, engineVersion: template.engineVersion, engineSHA256: template.engineSHA256, probeSHA256: template.probeSHA256, appVersion: template.appVersion, modelIdentifier: template.modelIdentifier, modelSHA256: template.modelSHA256, preprocessing: [], correspondenceNotes: [], definitions: template.definitions, samples: samples, pooledMetrics: template.pooledMetrics, aggregateMetrics: template.aggregateMetrics, comparedDuration: 0.14, processingFPS: nil)
        let controller = PlaybackController()
        defer { controller.close() }
        await controller.load(try VMAFCalculator.VMAFResult(analysis: analysis))
        #expect(controller.error == nil)
        #expect(controller.ready)
        controller.seek(index: 0); controller.seek(index: 2); controller.seek(index: 1)
        for _ in 0..<400 { if !controller.seeking { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(controller.selectedIndex == 1)
        #expect(controller.error == nil)
        let outputs = [AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]), AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])]
        controller.referencePlayer.currentItem?.add(outputs[0])
        controller.comparisonPlayer.currentItem?.add(outputs[1])
        for index in times.indices {
            controller.seek(index: index)
            for _ in 0..<200 { if !controller.seeking { break }; try await Task.sleep(for: .milliseconds(5)) }
            #expect(!controller.seeking)
            #expect(controller.error == nil)
            #expect(abs(controller.referencePlayer.currentTime().seconds - times[index]) < 0.00001)
            #expect(abs(controller.comparisonPlayer.currentTime().seconds - times[index]) < 0.00001)
            #expect(controller.selectedIndex == index)
            for output in outputs {
                var display = CMTime.invalid
                var pixel: CVPixelBuffer?
                let requested = CMTime(value: [0, 1, 3][index], timescale: 24)
                for _ in 0..<200 {
                    pixel = output.copyPixelBuffer(forItemTime: requested, itemTimeForDisplay: &display)
                    if pixel != nil { break }
                    try await Task.sleep(for: .milliseconds(5))
                }
                #expect(pixel != nil)
                #expect(CMTimeCompare(display, requested) == 0)
            }
        }
        controller.select(start: 1.0 / 24, end: 4.0 / 24)
        for _ in 0..<200 { if !controller.seeking { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(controller.selectedIndex == 1)
        #expect(controller.loop)
        controller.play()
        #expect(controller.playing)
        try await Task.sleep(for: .milliseconds(300))
        controller.pause()
        #expect(!controller.playing)
        #expect(abs(controller.referencePlayer.currentTime().seconds - controller.comparisonPlayer.currentTime().seconds) < 0.02)
    }
}

@MainActor
struct WorkflowGOPPlaybackTests {
    @Test func longGOP60FPSSeeksAndPlaybackRemainMatchedDuringNativeAnalysis() async throws {
        let engine = try AnalysisEngine.bundled()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gop-playback-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await Self.generateGOPMovie(url)
        let probe = try await OwnedProcess().run(executable: engine.ffprobe, arguments: ["-v", "error", "-select_streams", "v:0", "-show_entries", "frame=key_frame,pict_type", "-of", "json", url.path])
        let decoded = try #require(JSONSerialization.jsonObject(with: probe.stdout) as? [String: Any])
        let frameInfo = try #require(decoded["frames"] as? [[String: Any]])
        #expect(frameInfo.count == 720)
        let keyframes = frameInfo.enumerated().filter { ($0.element["key_frame"] as? Int) == 1 }.map(\.offset)
        #expect(keyframes.count <= 8)
        #expect(zip(keyframes, keyframes.dropFirst()).contains { $1 - $0 >= 200 })
        #expect(frameInfo.contains { ($0["pict_type"] as? String) == "B" })
        let result = try await VMAFCalculator().calculateVMAF(referenceVideo: url, comparisonVideo: url)
        #expect(result.frameCount == 720)
        let controller = PlaybackController()
        defer { controller.close() }
        await controller.load(result)
        #expect(controller.ready)
        controller.seek(index: 0); controller.seek(index: 719); controller.seek(index: 359)
        for _ in 0..<400 { if !controller.seeking { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(controller.selectedIndex == 359)
        #expect(controller.error == nil)
        let outputs = [AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]), AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])]
        controller.referencePlayer.currentItem?.add(outputs[0]); controller.comparisonPlayer.currentItem?.add(outputs[1])
        let calculator = VMAFCalculator()
        let (stream, continuation) = AsyncStream<AnalysisProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        calculator.onProgress = { continuation.yield($0) }
        let concurrent = Task.detached {
            defer { continuation.finish() }
            var configuration = AnalysisConfiguration(); configuration.threadCount = 1
            return try await calculator.calculateVMAF(referenceVideo: url, comparisonVideo: url, configuration: configuration)
        }
        defer { concurrent.cancel() }
        var iterator = stream.makeAsyncIterator()
        let progress = try #require(await iterator.next())
        #expect(!progress.isFinished)
        var beats: [Double] = []
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                beats.append(ProcessInfo.processInfo.systemUptime)
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        defer { heartbeat.cancel() }
        let exported = FileManager.default.temporaryDirectory.appendingPathComponent("gop-export-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: exported) }
        let exportTask = Task.detached {
            var options = ExportManager.ExportOptions(); options.includeFrameData = true
            try ExportManager().write(result: result, format: .json, options: options, to: exported)
        }
        defer { exportTask.cancel() }
        for index in [0, 1, 239, 240, 359, 478, 719] {
            controller.seek(index: index)
            for _ in 0..<400 { if !controller.seeking { break }; try await Task.sleep(for: .milliseconds(5)) }
            #expect(!controller.seeking)
            #expect(controller.error == nil)
            let pair = try #require(result.analysis?.samples[index].pair)
            let requested = try #require(PlaybackController.mediaTime(pts: pair.referencePTS, timeBase: pair.referenceTimeBase))
            for output in outputs {
                var display = CMTime.invalid
                var pixel: CVPixelBuffer?
                for _ in 0..<200 {
                    pixel = output.copyPixelBuffer(forItemTime: requested, itemTimeForDisplay: &display)
                    if pixel != nil { break }
                    try await Task.sleep(for: .milliseconds(5))
                }
                #expect(pixel != nil)
                #expect(CMTimeCompare(display, requested) == 0)
            }
        }
        controller.seek(index: 300)
        for _ in 0..<400 { if !controller.seeking { break }; try await Task.sleep(for: .milliseconds(5)) }
        controller.play()
        var liveMatches = 0
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(50))
            let time = controller.referencePlayer.currentTime()
            var referenceDisplay = CMTime.invalid, encodeDisplay = CMTime.invalid
            if outputs[0].copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &referenceDisplay) != nil,
               outputs[1].copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &encodeDisplay) != nil {
                #expect(CMTimeCompare(referenceDisplay, encodeDisplay) == 0)
                liveMatches += 1
            }
        }
        #expect(liveMatches >= 3)
        #expect(controller.playing)
        controller.pause()
        #expect(abs(controller.referencePlayer.currentTime().seconds - controller.comparisonPlayer.currentTime().seconds) < 1.0 / 60)
        let completed = try await concurrent.value
        #expect(completed.frameCount == 720)
        try await exportTask.value
        heartbeat.cancel(); await heartbeat.value
        let gaps = zip(beats, beats.dropFirst()).map { ($1 - $0) * 1000 }.sorted()
        let p95 = gaps.isEmpty ? 0 : gaps[min(gaps.count - 1, Int(Double(gaps.count) * 0.95))]
        let evidence: [String: Any] = ["duration_seconds": 12, "fps": 60, "frames": 720, "key_interval": 240, "keyframe_indices": keyframes, "b_frames": true,
            "live_matched_output_samples": liveMatches, "main_actor_heartbeat_samples": gaps.count,
            "main_actor_gap_p95_ms": p95, "main_actor_gap_max_ms": gaps.last ?? 0,
            "scope": "main-actor scheduling during exact seeks, native analysis and full JSON export; not compositor frame pacing"]
        print("PLAYBACK_SCHEDULING_JSON " + String(decoding: try JSONSerialization.data(withJSONObject: evidence, options: .sortedKeys), as: UTF8.self))
        print("PLAYBACK_GOP_EVIDENCE 12 seconds, 640x360, 60 fps, 720 frames, maximum keyint240, verified long GOP and B-frames; exact both-player display PTS at 0,1,239,240,359,478,719; concurrent native Standard analysis; live player skew < one frame")
    }
    private static func generateGOPMovie(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360,
            AVVideoPixelAspectRatioKey: [AVVideoPixelAspectRatioHorizontalSpacingKey: 1, AVVideoPixelAspectRatioVerticalSpacingKey: 1],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 240, AVVideoMaxKeyFrameIntervalDurationKey: 4.0,
                AVVideoAllowFrameReorderingKey: true, AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoAverageBitRateKey: 1_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<720 {
            for _ in 0..<500 { if input.isReadyForMoreMediaData { break }; try await Task.sleep(for: .milliseconds(5)) }
            try #require(input.isReadyForMoreMediaData)
            var pixel: CVPixelBuffer?
            try #require(CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_32BGRA, nil, &pixel) == kCVReturnSuccess)
            let buffer = try #require(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            let pixels = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt32.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer) / 4
            pixels.initialize(repeating: 0xff181818, count: stride * 360)
            let x = index * 3 % 580
            for y in 130..<190 { for column in x..<(x + 60) { pixels[y * stride + column] = 0xffdddddd } }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try #require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 60)))
        }
        writer.endSession(atSourceTime: CMTime(value: 12, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed, Comment(rawValue: writer.error?.localizedDescription ?? "Writer failed"))
    }

}
