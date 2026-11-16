//
//  VMAFTests.swift
//  VMAF
//
//  Created by Oliver Dougherty on 3/4/25.
//

import AppKit
import Foundation
import Testing
@testable import VMAF

struct VMAFTests {

    @Test func eachHostUsesOnlyItsNativeHelper() {
        // Foreign-architecture helpers are never candidates: launching the Intel
        // build on Apple Silicon would route analysis through Rosetta (gone in macOS 28).
        #expect(EngineHelper.resourceName(isAppleSilicon: true) == "ffmpeg")
        #expect(EngineHelper.resourceName(isAppleSilicon: false) == "ffmpeg.x86_64")
    }

    @Test func availabilityRequiresNativeHelperWithoutRosettaFallback() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = root.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let bundle = try #require(Bundle(url: root))
        let noSystem = root.appendingPathComponent("no-ffmpeg").path

        // Empty bundle: unavailable, and never the foreign helper.
        #expect(EngineHelper.availability(bundle: bundle, isAppleSilicon: true, systemFallbackPath: noSystem)
                == .unavailable(.helperMissing))

        let arm = resources.appendingPathComponent("ffmpeg")
        let intel = resources.appendingPathComponent("ffmpeg.x86_64")
        // Real Mach-O headers: thin arm64 and thin x86_64 magic + cputype.
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01, 0, 0, 0, 0]).write(to: arm)
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01, 0, 0, 0, 0]).write(to: intel)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: arm.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: intel.path)

        #expect(EngineHelper.availability(bundle: bundle, isAppleSilicon: true, systemFallbackPath: noSystem)
                == .bundled(path: arm.path))
        #expect(EngineHelper.availability(bundle: bundle, isAppleSilicon: false, systemFallbackPath: noSystem)
                == .bundled(path: intel.path))

        // Missing arm64 helper must NOT fall back to the Intel one; the system
        // engine is only used for non-.app hosts (source checkouts without built
        // resources). A shipped app with a missing helper is a hard error.
        try fm.removeItem(at: arm)
        #expect(EngineHelper.availability(bundle: bundle, isAppleSilicon: true, systemFallbackPath: noSystem)
                == .unavailable(.helperMissing))
        #expect(EngineHelper.availability(bundle: bundle, isAppleSilicon: true, systemFallbackPath: intel.path)
                == .systemFallback(path: intel.path))

        let appBundleRoot = root.appendingPathComponent("Shipped.app")
        try fm.createDirectory(at: appBundleRoot.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        let appBundle = try #require(Bundle(url: appBundleRoot))
        #expect(EngineHelper.availability(bundle: appBundle, isAppleSilicon: true, systemFallbackPath: intel.path)
                == .unavailable(.helperMissing))

        // A wrong-architecture file under the right name is a hard error, not a launch.
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01, 0, 0, 0, 0]).write(to: arm) // x86_64 bytes
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: arm.path)
        let mismatch = EngineHelper.availability(bundle: bundle, isAppleSilicon: true, systemFallbackPath: noSystem)
        guard case .unavailable(.helperArchitectureMismatch(let found)) = mismatch else {
            Issue.record("expected architecture mismatch, got \(mismatch)"); return
        }
        #expect(found == ["x86_64"])

        // Non-executable bits are reported distinctly.
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: arm.path)
        #expect(EngineHelper.availability(bundle: bundle, isAppleSilicon: true, systemFallbackPath: noSystem)
                == .unavailable(.helperNotExecutable))
    }

    @Test func readsFatMachOArchitectures() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: url) }
        var data = Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02]) // FAT_MAGIC, nfat_arch=2
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x0C, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) // arm64
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x07, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) // x86_64
        try data.write(to: url)
        #expect(EngineHelper.declaredMachOCPUTypes(at: url) == ["arm64", "x86_64"])

        // Non-Mach-O content reports nothing rather than guessing.
        try Data("not a binary".utf8).write(to: url)
        #expect(EngineHelper.declaredMachOCPUTypes(at: url).isEmpty)
    }

    @Test func decodesBothLibvmafMotionFormats() throws {
        let metrics = "\"vmaf\":67.5,\"integer_adm2\":0.93,\"integer_adm_scale0\":0.87,\"integer_adm_scale1\":0.91,\"integer_adm_scale2\":0.92,\"integer_adm_scale3\":0.97,\"integer_vif_scale0\":0.4,\"integer_vif_scale1\":0.6,\"integer_vif_scale2\":0.7,\"integer_vif_scale3\":0.8"
        let pooled = "\"pooled_metrics\":{\"vmaf\":{\"min\":58.9,\"max\":74.0,\"mean\":67.8,\"harmonic_mean\":67.7}},\"aggregate_metrics\":{}"
        let decoder = JSONDecoder()

        // libvmaf 3.2.0 (bundled engine): no `integer_motion` at all.
        let newJSON = "{\"frames\":[{\"frameNum\":0,\"metrics\":{\(metrics),\"integer_motion2\":1.5}}],\(pooled)}"
        let new = try decoder.decode(VMAFCalculator.VMAFData.self, from: Data(newJSON.utf8))
        let newFrame = try #require(new.frames.first)
        #expect(newFrame.vmafScore == 67.5)
        #expect(newFrame.integerMotion == nil) // legacy identity absent, not borrowed
        #expect(newFrame.integerMotion2 == 1.5)
        #expect(newFrame.motionReading?.feature == "integer_motion2")
        #expect(new.libvmafVersion == nil) // optional: missing key must not throw

        // libvmaf 2.x (older saved results): legacy identity only.
        let oldJSON = "{\"version\":\"e0d9b82d\",\"frames\":[{\"frameNum\":0,\"metrics\":{\"integer_motion\":2.5,\(metrics)}}],\(pooled)}"
        let old = try decoder.decode(VMAFCalculator.VMAFData.self, from: Data(oldJSON.utf8))
        #expect(old.libvmafVersion == "e0d9b82d")
        let oldFrame = try #require(old.frames.first)
        #expect(oldFrame.integerMotion == 2.5)
        #expect(oldFrame.integerMotion2 == nil)
        #expect(oldFrame.motionReading?.feature == "integer_motion")

        // Roundtrip preserves identity: a 3.x reading re-encodes as
        // `integer_motion2` and never resurrects the legacy key.
        let reDecoded = try decoder.decode(VMAFCalculator.VMAFData.self, from: JSONEncoder().encode(new))
        #expect(reDecoded.frames.first?.integerMotion == nil)
        #expect(reDecoded.frames.first?.integerMotion2 == 1.5)
        let reDecodedOld = try decoder.decode(VMAFCalculator.VMAFData.self, from: JSONEncoder().encode(old))
        #expect(reDecodedOld.frames.first?.integerMotion == 2.5)
        #expect(reDecodedOld.frames.first?.integerMotion2 == nil)
        #expect(reDecodedOld.libvmafVersion == "e0d9b82d")
    }

    @Test func motionlessFrameStillDecodes() throws {
        // Neither motion feature present: VMAF and ADM/VIF are unaffected.
        let json = "{\"frames\":[{\"frameNum\":0,\"metrics\":{\"vmaf\":67.5,\"integer_adm2\":0.93,\"integer_adm_scale0\":0.87,\"integer_adm_scale1\":0.91,\"integer_adm_scale2\":0.92,\"integer_adm_scale3\":0.97,\"integer_vif_scale0\":0.4,\"integer_vif_scale1\":0.6,\"integer_vif_scale2\":0.7,\"integer_vif_scale3\":0.8}}],\"pooled_metrics\":{\"vmaf\":{\"min\":58.9,\"max\":74.0,\"mean\":67.8,\"harmonic_mean\":67.7}},\"aggregate_metrics\":{}}"
        let data = try JSONDecoder().decode(VMAFCalculator.VMAFData.self, from: Data(json.utf8))
        #expect(data.frames.first?.motionReading == nil)
    }

}

struct ExportTests {
    private func frame(_ n: Int, motion: Double?, motion2: Double?) -> VMAFCalculator.FrameMetric {
        VMAFCalculator.FrameMetric(
            frameNumber: n, vmafScore: 60.0 + Double(n),
            integerMotion: motion, integerMotion2: motion2,
            integerAdm2: 0.9,
            integerAdmScales: [0.8, 0.85, 0.9, 0.95],
            integerVifScales: [0.4, 0.5, 0.6, 0.7])
    }
    private func result(_ frames: [VMAFCalculator.FrameMetric], version: String?) -> VMAFCalculator.VMAFResult {
        VMAFCalculator.VMAFResult(score: 70, minScore: 60, maxScore: 80, harmonicMean: 69,
                                  frameMetrics: frames, duration: 2, frameCount: frames.count,
                                  libvmafVersion: version)
    }

    @Test func csvFullFileImportsAsDocumentedSections() throws {
        let frames = [frame(1, motion: nil, motion2: 1.5), frame(2, motion: nil, motion2: nil)]
        let result = self.result(frames, version: "3.2.0")
        let csv = try ExportManager().exportToCSV(result: result, options: .init())

        // The *entire* exported file must consume cleanly, not just a prefix:
        // rectangular frame table, then titled metadata sections.
        let parsed = ExportManager.parse(csv)
        #expect(parsed.tableHeader == ["Frame Number", "Timestamp", "VMAF Score", "Motion (integer_motion2)", "ADM2"])
        #expect(parsed.frameRows.count == frames.count)
        for row in parsed.frameRows {
            #expect(row.count == 5, "non-uniform frame record: \(row)")
        }
        #expect(Double(parsed.frameRows[0][3]) == 1.5)  // value round-trips back
        #expect(parsed.frameRows[1][3] == "")           // absent motion stays empty
        #expect(parsed.aggregates["Overall VMAF Score"] == "70.0")
        #expect(parsed.engine["Metric"] == "libvmaf")
        #expect(parsed.engine["Version"] == "3.2.0")
        #expect(parsed.engine["Motion feature"] == "integer_motion2")
        #expect(parsed.unknownSections.isEmpty)        // nothing in the file went unconsumed

        // Frame-only export keeps engine provenance (reviewer: version was lost).
        var frameOnly = ExportManager.ExportOptions()
        frameOnly.includeAggregateMetrics = false
        let trimmed = try ExportManager().exportToCSV(result: result, options: frameOnly)
        let trimmedParsed = ExportManager.parse(trimmed)
        #expect(trimmedParsed.aggregates.isEmpty)
        #expect(trimmedParsed.engine["Version"] == "3.2.0")
        #expect(trimmedParsed.unknownSections.isEmpty)
        #expect(trimmedParsed.frameRows.count == 2)
    }

    @Test func jsonOmitsAbsentMotionInsteadOfZeroFilling() throws {
        let manager = ExportManager()
        let frames = [frame(1, motion: nil, motion2: 1.5), frame(2, motion: nil, motion2: nil)]
        let data = try manager.exportToJSON(result: result(frames, version: "3.2.0"), options: .init())
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outFrames = try #require(root["frames"] as? [[String: Any]])
        #expect(outFrames.count == 2)
        let withMotion = outFrames[0]
        #expect(withMotion["integer_motion2"] as? Double == 1.5)
        #expect(withMotion["motion"] == nil) // no legacy key invented
        #expect(withMotion["integer_motion"] == nil)
        let withoutMotion = outFrames[1]
        #expect(withoutMotion["motion"] == nil && withoutMotion["integer_motion2"] == nil)
        // Absent must stay absent: the frame dict carries no fabricated 0.0.
        #expect(!withoutMotion.values.contains { ($0 as? Double) == 0.0 })
        let engine = try #require(root["engine"] as? [String: Any])
        #expect(engine["version"] as? String == "3.2.0")
    }

    @Test func engineUnavailableReachesUIAsActionableMessage() {
        // The UI catches `Error` and calls `.localizedDescription`; only the
        // LocalizedError bridge surfaces the reinstall instruction.
        let caught: Error = VMAFCalculator.VMAFError.engineUnavailable(.helperMissing)
        #expect(caught.localizedDescription.contains("Reinstall"))
        let mismatch: Error = VMAFCalculator.VMAFError.engineUnavailable(.helperArchitectureMismatch(found: ["x86_64"]))
        #expect(mismatch.localizedDescription.contains("x86_64"))
        // Other cases must also bridge rather than fall back to Cocoa text.
        let model: Error = VMAFCalculator.VMAFError.modelNotFound("vmaf_v0.6.1")
        #expect(model.localizedDescription.contains("vmaf_v0.6.1"))
    }

    @Test func pdfColumnsWidenToTheLongestHeader() {
        let font = NSFont.systemFont(ofSize: 12)
        let widths = PDFGenerator.tableColumnWidths(
            headers: ["Frame", "Time", "VMAF", "Motion (integer_motion2)", "ADM2"], font: font)
        #expect(widths.count == 5)
        #expect(widths[3] > 150) // the long header gets its own space
        #expect(widths.reduce(0, +) < 612 - 48 - 36) // fits one US Letter page
        // Every column is at least as wide as its own text plus padding.
        for (header, width) in zip(["Frame", "Time", "VMAF", "Motion (integer_motion2)", "ADM2"], widths) {
            let text = (header as NSString).size(withAttributes: [.font: font]).width
            #expect(width >= text, "\(header) would overflow its \(width)pt column")
        }
    }

}
