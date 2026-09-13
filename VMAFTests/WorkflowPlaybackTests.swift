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
