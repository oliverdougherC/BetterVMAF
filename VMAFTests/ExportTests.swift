import Foundation
import Testing
import PDFKit
@testable import VMAF

enum ExportFixture {
    static func analysis(bytes: Int64 = 500, vmaf: Double = 92, model: String = "pinned-model", sourceHash: String = String(repeating: "a", count: 64), timestamps: [Double] = [0, 0.04, 0.1]) -> AnalysisResult {
        let file = AnalysisFileIdentity(url: URL(fileURLWithPath: "/fixtures/source, quoted \"雪\".mp4"), sha256: sourceHash, byteCount: 1000, modifiedAt: Date(timeIntervalSince1970: 100))
        let encode = AnalysisFileIdentity(url: URL(fileURLWithPath: "/fixtures/encode.mp4"), sha256: String(repeating: "b", count: 64), byteCount: bytes, modifiedAt: Date(timeIntervalSince1970: 100))
        let stream = AnalysisStream(index: 0, codec: "h264", width: 1920, height: 1080, pixelFormat: "yuv420p", bitDepth: 8, timeBase: "1/1000", averageFrameRate: "25/1", sampleAspectRatio: "1:1", rotation: 0, fieldOrder: "progressive", colorMatrix: "bt709", colorPrimaries: "bt709", colorTransfer: "bt709", colorRange: "tv", chromaLocation: "left", duration: 0.14)
        let samples = timestamps.enumerated().map { index, time in
            AnalysisMetricSample(pair: AnalysisFramePair(index: index, referencePTS: Int64(5000 + time * 1000), comparisonPTS: Int64(2000 + time * 1000), referenceTimeBase: "1/1000", comparisonTimeBase: "1/1000", referenceTimestamp: 5 + time, comparisonTimestamp: 2 + time, timestamp: time, duration: index + 1 < timestamps.count ? timestamps[index + 1] - time : 0.04), values: ["vmaf": .finite(vmaf), "xpsnr_y": .positiveInfinity, "xpsnr_u": .finite(42), "xpsnr_v": .finite(40), "cambi_source": .finite(1), "cambi_encode": .finite(3), "cambi_full_reference": .finite(2), "undefined_fixture": .undefined, "absent_fixture": .unavailable])
        }
        return AnalysisResult(schemaVersion: 1, runID: UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!, createdAt: Date(timeIntervalSince1970: 100), reference: file, comparison: encode, referenceStream: stream, comparisonStream: stream, configuration: AnalysisConfiguration(), engineVersion: "FFmpeg pinned fixture", engineSHA256: "engine-hash", probeSHA256: "probe-hash", appVersion: "1.0-test", modelIdentifier: model, modelSHA256: model, preprocessing: ["Explicit SDR conversion"], correspondenceNotes: ["Matched original PTS"], definitions: AnalysisService.definitions(model: model, hash: model, libraryVersion: "fixture", profile: .standard1080p), samples: samples, pooledMetrics: ["vmaf": ["mean": .finite(vmaf), "min": .finite(vmaf), "max": .finite(vmaf)], "xpsnr_y": ["native_average": .positiveInfinity], "xpsnr_u": ["native_average": .finite(42)], "xpsnr_v": ["native_average": .finite(40)], "cambi_source": ["mean": .finite(1)], "cambi_encode": ["mean": .finite(3)], "cambi_full_reference": ["mean": .finite(2)]], aggregateMetrics: ["xpsnr_min_plane": .finite(40)], comparedDuration: 0.14, processingFPS: 25)
    }
    static func result() -> VMAFCalculator.VMAFResult { try! VMAFCalculator.VMAFResult(analysis: analysis()) }
}

struct ExportTests {
    @Test func fullJSONRoundTripsImmutableInputsPTSAndNonfiniteValues() throws {
        let original = ExportFixture.result()
        var options = ExportManager.ExportOptions(); options.includeFrameData = true
        let data = try ExportManager().exportToJSON(result: original, options: options)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AnalysisResult.self, from: data)
        #expect(decoded.reference == original.analysis?.reference)
        #expect(decoded.comparison == original.analysis?.comparison)
        #expect(decoded.configuration == original.analysis?.configuration)
        #expect(decoded.framePairs == original.analysis?.framePairs)
        #expect(decoded.samples[0].values["xpsnr_y"] == .positiveInfinity)
        #expect(decoded.samples[0].values["absent_fixture"] == .unavailable)
        #expect(decoded.samples[0].values["undefined_fixture"] == .undefined)
        #expect(decoded.pooledMetrics["xpsnr_y"]?["native_average"] == .positiveInfinity)
        #expect(decoded.samples[0].pair.referenceTimestamp == 5)
        #expect(decoded.samples[0].pair.comparisonTimestamp == 2)
    }
    @Test func optionsOmitPayloadsAndCSVPreservesEscapedProvenance() throws {
        var options = ExportManager.ExportOptions(); options.includeAggregateMetrics = false
        let data = try ExportManager().exportToJSON(result: ExportFixture.result(), options: options)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["samples"] == nil)
        #expect(json["aggregateMetrics"] == nil)
        #expect(json["pooledMetrics"] == nil)
        #expect(json["reference"] != nil)
        #expect(json["definitions"] != nil)
        options.includeFrameData = true
        let csv = try ExportManager().exportToCSV(result: ExportFixture.result(), options: options)
        #expect(csv.contains("+infinity"))
        #expect(csv.contains("\"frame\",\"1\",\"0.04\",\"0.060000000000000005\",\"5.04\",\"2.04\""))
        #expect(!csv.contains("\"upstream_pool\""))
        #expect(ExportManager.csvCell("a,\"b\"\nc") == "\"a,\"\"b\"\"\nc\"")
    }
    @Test func summaryPDFIsOneVectorPageAndHonorsAggregateSelection() throws {
        let manager = ExportManager()
        let data = try manager.exportToPDF(result: ExportFixture.result(), options: .init())
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1)
        let text = pdf.string ?? ""
        #expect(text.contains("VMAF v1"))
        #expect(text.contains("92.0000"))
        #expect(text.contains("40.0000"))
        #expect(text.contains("Source CAMBI"))
        #expect(text.contains("source, quoted"))
        var options = ExportManager.ExportOptions(); options.includeAggregateMetrics = false; options.includeGraphs = false
        let omitted = try #require(PDFDocument(data: manager.exportToPDF(result: ExportFixture.result(), options: options)))
        #expect(!(omitted.string ?? "").contains("VMAF v1"))
        #expect(!(omitted.string ?? "").contains("XPSNR"))
        // Durable local QA artifact for PDF rendering; never added to source control.
        let qaURL = FileManager.default.temporaryDirectory.appendingPathComponent("bettervmaf-summary-qa.pdf")
        try data.write(to: qaURL)
        print("PDF_QA_PATH \(qaURL.path)")
        print("PDF_QA_BASE64 \(data.base64EncodedString())")
    }
    @Test func cancellationPreservesExistingDestinationAndRemovesStaging() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("report.json")
        try Data("previous report".utf8).write(to: destination)
        let task = Task.detached {
            try? await Task.sleep(for: .milliseconds(20))
            try ExportManager().write(result: ExportFixture.result(), format: .csv, options: .init(), to: destination)
        }
        task.cancel()
        do { try await task.value; Issue.record("Cancelled export completed") } catch is CancellationError { }
        #expect(try String(contentsOf: destination, encoding: .utf8) == "previous report")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["report.json"])
    }
    @Test func atomicExportCreatesAndReplacesDestination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("report.json")
        let manager = ExportManager()
        try manager.write(result: ExportFixture.result(), format: .json, options: .init(), to: destination)
        var options = ExportManager.ExportOptions(); options.includeFrameData = true
        try manager.write(result: ExportFixture.result(), format: .json, options: options, to: destination)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AnalysisResult.self, from: Data(contentsOf: destination))
        #expect(decoded.samples.count == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["report.json"])
    }
    @Test func nativePoolingDeterminesCompatibleNonDominatedChoices() throws {
        let small = ExportFixture.analysis(bytes: 400, vmaf: 95)
        let large = ExportFixture.analysis(bytes: 600, vmaf: 90)
        #expect(ComparisonTradeoffs.nativeValue("vmaf", in: small) == .finite(95))
        #expect(ComparisonTradeoffs.nativeValue("xpsnr_y", in: small) == .positiveInfinity)
        #expect(ComparisonTradeoffs.dominates(small, large))
        #expect(!ComparisonTradeoffs.dominates(large, small))
        #expect(try ComparisonTradeoffs.compatibilityKey(small) == ComparisonTradeoffs.compatibilityKey(large))
        #expect(try ComparisonTradeoffs.compatibilityKey(small) != ComparisonTradeoffs.compatibilityKey(ExportFixture.analysis(model: "different-model")))
        #expect(try ComparisonTradeoffs.compatibilityKey(small) != ComparisonTradeoffs.compatibilityKey(ExportFixture.analysis(timestamps: [0, 0.05, 0.1])))
    }
}
