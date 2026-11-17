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

// MARK: - Heat map

/// The heat map replaced the line graph, so these cover the behaviour the plot
/// depends on: absolute colour bands, viewport-sized level of detail, clean
/// axis strides, and pan/zoom that cannot escape the clip.
struct QualityTimelineTests {
    private func frames(_ scores: [Double]) -> [VMAFCalculator.FrameMetric] {
        scores.enumerated().map { index, score in
            VMAFCalculator.FrameMetric(
                frameNumber: index + 1, vmafScore: score,
                integerMotion: 4.0, integerMotion2: nil, integerAdm2: 0.95,
                integerAdmScales: [0.9, 0.9, 0.9, 0.9],
                integerVifScales: [0.9, 0.9, 0.9, 0.9])
        }
    }

    @Test func bandsAreAbsoluteNotClipRelative() {
        // CA-07: 99.1 must not read as "poor" just because it is a clip minimum.
        #expect(QualityBand(vmafScore: 99.1) == .excellent)
        #expect(QualityBand(vmafScore: 95.0) == .good)
        #expect(QualityBand(vmafScore: 94.9) == .fair)
        #expect(QualityBand(vmafScore: 89.99) == .poor)
    }

    @Test func rampInterpolatesContinuouslyAndHonoursAnchors() {
        // Regression: an early-return loop made every score snap to the next
        // anchor's colour, so the ramp was an 8-step staircase and the 0 anchor
        // was unreachable. Adjacent scores must differ...
        #expect(QualityScale.rgb(at: 88.1) != QualityScale.rgb(at: 88.5))
        #expect(QualityScale.rgb(at: 89.0) != QualityScale.rgb(at: 89.5))
        #expect(QualityScale.rgb(at: 96.0) != QualityScale.rgb(at: 96.5))
        // ...halfway between two anchors is their linear-light midpoint...
        let mid = QualityScale.rgb(at: 89.0)
        let a = QualityScale.rgb(at: 88.0)
        let b = QualityScale.rgb(at: 90.0)
        #expect(abs(mid.red - (a.red + b.red) / 2) < 0.001)
        #expect(abs(mid.green - (a.green + b.green) / 2) < 0.001)
        // ...anchors display exactly as authored (the table is sRGB, blending is
        // linear, so a round trip through nsColor must return the authored byte).
        func displayComponents(_ score: Double) -> (Double, Double, Double) {
            let c = QualityScale.rgb(at: score).nsColor.usingColorSpace(.sRGB)!
            return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        }
        for (score, authored) in [(88.0, (0.89, 0.17, 0.16)), (90.0, (0.94, 0.45, 0.13)),
                                  (97.0, (0.55, 0.79, 0.22)), (99.0, (0.18, 0.74, 0.32)),
                                  (0.0, (0.55, 0.10, 0.10))] {
            let got = displayComponents(score)
            #expect(abs(got.0 - authored.0) < 1.0 / 255, "\(score) red \(got.0)")
            #expect(abs(got.1 - authored.1) < 1.0 / 255, "\(score) green \(got.1)")
            #expect(abs(got.2 - authored.2) < 1.0 / 255, "\(score) blue \(got.2)")
        }
    }

    @Test func colorRampHeatsUpWithQuality() {
        // Regression: normalizing against a clip's min/max divided by zero when
        // every frame scored the same, and fell through to "excellent".
        #expect(QualityScale.rgb(at: 0) != QualityScale.rgb(at: 100))
        // Across Fair→Good→Excellent the hue travels orange→yellow→green→teal:
        // red drains monotonically, green climbs.
        let fair = QualityScale.rgb(at: 92.5)
        let good = QualityScale.rgb(at: 97)
        let excellent = QualityScale.rgb(at: 99.8)
        #expect(fair.red > good.red && good.red > excellent.red)
        #expect(fair.green < good.green)
        // Every band gets its own colour: four distinct samples, no ties.
        let sampled = [QualityScale.rgb(at: 85), fair, good, excellent]
        #expect(Set(sampled).count == sampled.count)
    }

    @Test func constantClipGetsNonZeroScoreRange() {
        let flat = QualityTimeline(metrics: frames(Array(repeating: 97.5, count: 10)))
        #expect(flat.scoreRange.lowerBound < flat.scoreRange.upperBound)
        #expect(flat.scoreRange.contains(97.5))
    }

    @Test func emptyTimelineHasUsableDomains() {
        let empty = QualityTimeline(metrics: [])
        #expect(empty.frameCount == 0)
        #expect(empty.scoreRange.lowerBound < empty.scoreRange.upperBound)
        #expect(empty.worstIndex == nil)
        #expect(empty.nearestIndex(for: 3) == nil)
        #expect(empty.slice(covering: 0...10).isEmpty)
        #expect(empty.buckets(count: 100, covering: 0...10).isEmpty)
    }

    @Test func singleFrameWithNegativeTimestampStillRenders() {
        // libvmaf numbers frames from zero, so `timestamp = (frameNum - 1) / 30`
        // puts the only frame of a one-frame result at -0.0333s (CA-04). The
        // domain fallback used to be `0...1`, which excluded it and drew a
        // blank plot for real data.
        let only = VMAFCalculator.FrameMetric(
            frameNumber: 0, vmafScore: 91.25,
            integerMotion: nil, integerMotion2: nil, integerAdm2: 0.95,
            integerAdmScales: [0.9, 0.9, 0.9, 0.9],
            integerVifScales: [0.9, 0.9, 0.9, 0.9])
        let timeline = QualityTimeline(metrics: [only])
        let domain = timeline.timeRange
        #expect(domain.contains(timeline.time(at: 0)), "one-frame domain \(domain) excludes its frame")
        #expect(domain.upperBound > domain.lowerBound)
        #expect(timeline.slice(covering: domain).count == 1)
        let buckets = timeline.buckets(count: 100, covering: domain)
        #expect(buckets.reduce(0) { $0 + $1.frameCount } == 1)
        #expect(buckets.first?.minScore == 91.25)
    }

    @Test func bucketsPreserveExactMinAndMaxAndCoverEveryFrame() {
        // 30 fps, 3,000 frames, one deliberate dip: a wide view must not lose it.
        var scores = (0..<3000).map { 95.0 + Double($0 % 5) }
        scores[1500] = 42.0
        let timeline = QualityTimeline(metrics: frames(scores))
        let domain = timeline.timeRange
        let buckets = timeline.buckets(count: 200, covering: domain)

        #expect(!buckets.isEmpty)
        #expect(buckets.count <= 200)
        #expect(buckets.map(\.minScore).min() == 42.0)
        #expect(buckets.map(\.maxScore).max() == 99.0)
        // Every frame lands in exactly one bucket, and totals add up.
        #expect(buckets.reduce(0) { $0 + $1.frameCount } == scores.count)
        for (left, right) in zip(buckets, buckets.dropFirst()) {
            #expect(right.startIndex == left.endIndex)
            #expect(right.startTime >= left.endTime - 0.0001)
        }
    }

    @Test func gridCountsEveryVisibleFrameOnce() {
        let timeline = QualityTimeline(metrics: frames((0..<1000).map { 90.0 + Double($0 % 100) / 10.0 }))
        let domain = timeline.timeRange
        let grid = timeline.grid(columns: 300, bins: 60, domain: domain, scoreDomain: 90...100)
        #expect(grid.cells.reduce(0) { $0 + $1.count } == 1000)
        #expect(grid.maxCount >= 1)
        // Cells never invent rows outside the grid.
        #expect(grid.cells.allSatisfy { $0.bin >= 0 && $0.bin < grid.bins })
    }

    @Test func nearestIndexMatchesLinearSearch() {
        let timeline = QualityTimeline(metrics: frames((0..<5000).map { 95.0 + Double($0 % 40) / 10.0 }))
        for probe in stride(from: 0.0, through: 166.6, by: 0.37) {
            let fast = timeline.nearestIndex(for: probe)
            let slow = (0..<5000).min {
                abs(timeline.time(at: $0) - probe) < abs(timeline.time(at: $1) - probe)
            }
            #expect(fast == slow, "nearestIndex disagreed with linear scan at \(probe)s")
        }
    }

    @Test func nonMonotonicTimesStillResolve() {
        // Sampling can emit out-of-order frames; the plot must not crash or
        // silently pick a wrong index.
        var built = frames((0..<200).map { _ in 96.0 })
        built[40] = VMAFCalculator.FrameMetric(frameNumber: 5, vmafScore: 80.0, integerMotion: nil,
            integerMotion2: nil, integerAdm2: 0.9, integerAdmScales: [0.9,0.9,0.9,0.9], integerVifScales: [0.9,0.9,0.9,0.9])
        let timeline = QualityTimeline(metrics: built)
        #expect(!timeline.isTimeMonotonic)
        #expect(timeline.nearestIndex(for: timeline.time(at: 5)) != nil)
        let buckets = timeline.buckets(count: 50, covering: timeline.timeRange)
        #expect(buckets.reduce(0) { $0 + $1.frameCount } == 200)
        // The misordered frame (index 40, timestamp 0.133s, score 80) must be
        // summarised in the column that actually contains its time; the old
        // scan cursor filed it seconds away under whichever column it reached
        // while the totals still added up.
        let dipTime = timeline.time(at: 40)
        let holder = buckets.filter { $0.minScore == 80.0 }
        #expect(holder.count == 1)
        #expect(holder[0].startTime <= dipTime)
        #expect(dipTime <= holder[0].endTime)
        #expect(holder[0].worstIndex == 40)
        // Bucket time spans must not overlap and stay inside the window.
        for (left, right) in zip(buckets, buckets.dropFirst()) {
            #expect(right.startTime >= left.endTime - 0.0001)
        }
        #expect(buckets.first!.startTime >= timeline.timeRange.lowerBound)
        #expect(buckets.last!.endTime <= timeline.timeRange.upperBound + 0.0001)
    }

    @Test func bandRunStopsAtABetterFrame() {
        // Excellent frames surround a Good stretch: the run is the stretch, and
        // an excellent frame has no concern interval to escalate.
        var scores = [Double](repeating: 99.5, count: 30)
        for index in 10...19 { scores[index] = 96.0 }
        let timeline = QualityTimeline(metrics: frames(scores))
        #expect(timeline.bandRun(containing: 12) == 10...19)
        #expect(timeline.bandRun(containing: 0) == nil)

        // A dip inside a worse stretch extends only through the worse part.
        // Each band reports its own extent, and a worse frame inside it widens
        // the interval of the shoulder band but not of the worst band.
        var graded = [Double](repeating: 99.0, count: 20)
        graded[5] = 91.0   // Fair
        graded[6] = 85.0   // Poor
        graded[7] = 92.0   // Fair
        let mixed = QualityTimeline(metrics: frames(graded))
        #expect(mixed.bandRun(containing: 5) == 5...7)   // Fair-or-worse stretch
        #expect(mixed.bandRun(containing: 6) == 6...6)   // the Poor frame alone
        #expect(mixed.bandRun(containing: 7) == 5...7)
    }

    @Test func detailLevelDowngradesAsFramesPerPixelGrow() {
        #expect(QualityTimeline.detailLevel(framesPerPixel: 0.1) == .exactFrames)
        #expect(QualityTimeline.detailLevel(framesPerPixel: 1.0) == .exactFrames)
        #expect(QualityTimeline.detailLevel(framesPerPixel: 3) == .density)
        #expect(QualityTimeline.detailLevel(framesPerPixel: 24) == .density)
        #expect(QualityTimeline.detailLevel(framesPerPixel: 100) == .envelope)
        // Plotted marks therefore stay bounded by the viewport, not the clip.
        let columns = QualityTimeline.densityColumns(width: 1000)
        #expect(columns == 500)
    }

    @Test func timeAxisNeverLabelsEverySecond() {
        // 2,786 one-second labels is the cluttered axis being fixed.
        let wide = 0...2786.0
        let ticks = TimeAxis.ticks(in: wide, width: 1350)
        #expect(ticks.values.count <= 20)
        #expect(ticks.spacing >= 60)
        // Ticks are whole multiples of their stride and inside the window.
        for tick in ticks.values {
            #expect(abs(tick / ticks.spacing - (tick / ticks.spacing).rounded()) < 0.0001)
            #expect(tick >= wide.lowerBound && tick <= wide.upperBound)
        }

        let narrow = TimeAxis.ticks(in: 12.0...13.0, width: 1350)
        #expect(narrow.spacing < 1)
        #expect(!narrow.values.isEmpty)
        // Sub-second ticks stay distinguishable in the label.
        #expect(Set(narrow.values.map { TimeFormat.string($0, spacing: narrow.spacing) }).count == narrow.values.count)
    }

    @Test func scoreAxisUsesRoundNumbers() {
        let full = ScoreAxis.ticks(in: 0...100, height: 300)
        #expect(full.values.allSatisfy { $0 == $0.rounded() })
        #expect(full.values.first == 0)
        #expect(full.values.last == 100)
        #expect(full.values.count <= 16)

        let fine = ScoreAxis.ticks(in: 96.3...97.1, height: 300)
        #expect(fine.spacing < 1)
        #expect(fine.values.count > 2)
        // Labels carry enough digits to tell adjacent ticks apart.
        #expect(Set(fine.values.map(fine.label)).count == fine.values.count)
    }

    @Test func timeFormatCoversHoursAndFractions() {
        #expect(TimeFormat.string(65, spacing: 5) == "1:05")
        #expect(TimeFormat.string(3725, spacing: 60) == "1:02:05")
        #expect(TimeFormat.string(21.5, spacing: 0.5) == "0:21.5")
        #expect(TimeFormat.string(21.0, spacing: 0.5) == "0:21")
        #expect(TimeFormat.string(23.7, spacing: 0.1) == "0:23.7")
    }

    @Test func durationsAndFrameTimesReadAsQuantities() {
        // A 0.77-second clip used to report "· 0:00", which looks like a
        // position rather than a length.
        #expect(TimeFormat.duration(0.766_6) == "0.77s")
        #expect(TimeFormat.duration(12.34) == "12.3s")
        #expect(TimeFormat.duration(2786) == "46:26")
        // Frame times need the millisecond the old "%.1f" truncated.
        #expect(TimeFormat.exact(0.766_6) == "0:00.767")
        #expect(TimeFormat.exact(65.5) == "1:05.500")
        #expect(TimeFormat.exact(3725.25) == "1:02:05.250")
        // The app's known negative first timestamp stays well-formed.
        #expect(TimeFormat.exact(-0.0333) == "-0:00.033")
    }
}

@MainActor
struct HeatmapViewportTests {
    private func frames(_ count: Int) -> [VMAFCalculator.FrameMetric] {
        (1...count).map { index in
            VMAFCalculator.FrameMetric(
                frameNumber: index, vmafScore: 95.0 + Double(index % 5),
                integerMotion: nil, integerMotion2: nil, integerAdm2: 0.95,
                integerAdmScales: [0.9, 0.9, 0.9, 0.9],
                integerVifScales: [0.9, 0.9, 0.9, 0.9])
        }
    }

    private let geometry = ChartGeometry(size: CGSize(width: 1350, height: 300))

    @Test func defaultWindowShowsTheWholeClip() {
        let timeline = QualityTimeline(metrics: frames(1439))
        let viewport = HeatmapViewport()
        #expect(!viewport.isZoomed)
        #expect(viewport.displayDomain(in: timeline, geometry: geometry) == timeline.timeRange)
    }

    @Test func zoomKeepsTheAnchorPixelStill() {
        let timeline = QualityTimeline(metrics: frames(1439))
        let viewport = HeatmapViewport()
        let anchor = 1000.0 / 30.0
        let before = geometry.x(for: anchor, domain: viewport.displayDomain(in: timeline, geometry: geometry))
        viewport.zoom(by: 8, around: anchor, in: timeline, geometry: geometry)
        let after = geometry.x(for: anchor, domain: viewport.displayDomain(in: timeline, geometry: geometry))
        #expect(abs(after - before) < 0.5, "zoom slid the anchor across the plot")
        #expect(viewport.zoom > 7.9)
    }

    @Test func windowCannotBeDraggedPastEitherEnd() {
        let timeline = QualityTimeline(metrics: frames(1439))
        let viewport = HeatmapViewport()
        viewport.setZoom(64, in: timeline, geometry: geometry)
        // `drag` takes the gesture's cumulative translation from its origin.
        // A ~0.75s window across ~47s of clip needs a very long drag to reach
        // the end; 1M px overshoots, and the clamp must absorb it.
        viewport.drag(byPixels: -1_000_000, in: timeline, geometry: geometry)
        viewport.endDrag()
        var domain = viewport.displayDomain(in: timeline, geometry: geometry)
        #expect(domain.upperBound <= timeline.timeRange.upperBound + 0.001)
        // Division by the zoom factor is not exact, so the end is reached to
        // within float dust rather than bit-for-bit.
        #expect(abs(domain.upperBound - timeline.timeRange.upperBound) < 0.0001)

        viewport.drag(byPixels: 1_000_000, in: timeline, geometry: geometry)
        viewport.endDrag()
        domain = viewport.displayDomain(in: timeline, geometry: geometry)
        #expect(domain.lowerBound >= timeline.timeRange.lowerBound - 0.001)
        #expect(abs(domain.lowerBound - timeline.timeRange.lowerBound) < 0.0001)
    }

    @Test func windowLengthSurvivesPanningAtFixedZoom() {
        let timeline = QualityTimeline(metrics: frames(1439))
        let viewport = HeatmapViewport()
        viewport.setZoom(16, in: timeline, geometry: geometry)
        let before = viewport.displayDomain(in: timeline, geometry: geometry)
        viewport.pan(byPixels: -400, in: timeline, geometry: geometry)
        let after = viewport.displayDomain(in: timeline, geometry: geometry)
        #expect(abs((after.upperBound - after.lowerBound) - (before.upperBound - before.lowerBound)) < 0.001)
    }

    @Test func zoomIsBoundedByWhatFramesCanBeShown() {
        let timeline = QualityTimeline(metrics: frames(1439))
        let viewport = HeatmapViewport()
        viewport.setZoom(1_000_000, in: timeline, geometry: geometry)
        #expect(viewport.zoom == viewport.maximumZoom(in: timeline, geometry: geometry))
        let domain = viewport.displayDomain(in: timeline, geometry: geometry)
        // The finest window still shows a hoverable handful of frames.
        #expect(timeline.slice(covering: domain).count >= 2)
    }

    @Test func degenerateAndEmptyResultsStayFinite() {
        let viewport = HeatmapViewport()
        #expect(viewport.displayDomain(in: QualityTimeline(metrics: []), geometry: geometry).lowerBound.isFinite)
        #expect(viewport.scoreDomain(in: QualityTimeline(metrics: [])).lowerBound.isFinite)

        let single = QualityTimeline(metrics: frames(1))
        let domain = viewport.displayDomain(in: single, geometry: geometry)
        #expect(domain.upperBound > domain.lowerBound)
        #expect(!viewport.isZoomed)

        let flat = QualityTimeline(metrics: QualityTimelineTestsFrames.constant(200, score: 97.5))
        let scores = viewport.scoreDomain(in: flat)
        #expect(scores.upperBound > scores.lowerBound)
        #expect(scores.contains(97.5))
    }

    @Test func autoRangeRevealsANarrowBandButStaysAbsolute() {
        // 93.75...100 spread over the full plot height instead of 6% of it.
        let timeline = QualityTimeline(metrics: QualityTimelineTestsFrames.ramp)
        let viewport = HeatmapViewport()
        let auto = viewport.scoreDomain(in: timeline)
        #expect(auto.lowerBound < timeline.scoreRange.lowerBound)
        #expect(auto.upperBound > timeline.scoreRange.upperBound)
        #expect(auto.upperBound - auto.lowerBound < 10)
        viewport.verticalScale = .full
        #expect(viewport.scoreDomain(in: timeline) == 0...100)
    }

    @Test func focusCentresTheWorstFrameInsideTheWindow() {
        guard let worst = QualityTimeline(metrics: QualityTimelineTestsFrames.ramp).worstIndex else {
            Issue.record("ramp fixture should have a worst frame"); return
        }
        let timeline = QualityTimeline(metrics: QualityTimelineTestsFrames.ramp)
        let viewport = HeatmapViewport()
        viewport.focus(onIndex: worst, in: timeline, geometry: geometry)
        let domain = viewport.displayDomain(in: timeline, geometry: geometry)
        #expect(domain.contains(timeline.time(at: worst)))
        #expect(viewport.isZoomed)
    }
}

/// Shared fixtures for the viewport tests above.
enum QualityTimelineTestsFrames {
    static func constant(_ count: Int, score: Double) -> [VMAFCalculator.FrameMetric] {
        (1...count).map { index in
            VMAFCalculator.FrameMetric(frameNumber: index, vmafScore: score, integerMotion: 4,
                integerMotion2: nil, integerAdm2: 0.95,
                integerAdmScales: [0.9, 0.9, 0.9, 0.9], integerVifScales: [0.9, 0.9, 0.9, 0.9])
        }
    }

    /// The real-world case from the bug report: a good encode whose frames sit
    /// between 93.75 and 100, so a 0-100 axis hides every difference.
    static var ramp: [VMAFCalculator.FrameMetric] {
        (0..<1439).map { index in
            let score = 93.75 + (Double(index % 187) / 186.0) * 6.25
            return VMAFCalculator.FrameMetric(frameNumber: index + 1, vmafScore: min(100, score),
                integerMotion: 4.0, integerMotion2: nil, integerAdm2: 0.95,
                integerAdmScales: [0.9, 0.9, 0.9, 0.9], integerVifScales: [0.9, 0.9, 0.9, 0.9])
        }
    }
}
