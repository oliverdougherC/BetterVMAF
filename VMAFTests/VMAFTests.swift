//
//  VMAFTests.swift
//  VMAFTests
//
//  Created by Oliver Dougherty on 3/4/25.
//

import Foundation
import Testing
@testable import VMAF

struct VMAFTests {

    @Test func bundledFfmpegMatchesHostArchitecture() {
        // Intel Macs get exactly one helper; Apple Silicon prefers arm64 and keeps the
        // Intel build only as a last resort so Rosetta is never on the default path.
        #expect(EngineHelper.candidateOrder(isAppleSilicon: true) == ["ffmpeg", "ffmpeg.x86_64"])
        #expect(EngineHelper.candidateOrder(isAppleSilicon: false) == ["ffmpeg.x86_64"])
    }

    @Test func selectionPrefersNativeHelperAndFlagsRosettaFallback() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = root.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let bundle = Bundle(url: root)

        // No helpers present yet.
        let anyBundle = try #require(bundle)
        #expect(EngineHelper.selection(bundle: anyBundle, isAppleSilicon: true) == nil)

        let arm = resources.appendingPathComponent("ffmpeg")
        let intel = resources.appendingPathComponent("ffmpeg.x86_64")
        try Data([0xFF]).write(to: arm)
        try Data([0xFF]).write(to: intel)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: arm.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: intel.path)
        let native = EngineHelper.selection(bundle: anyBundle, isAppleSilicon: true)
        #expect(native?.path == arm.path)
        #expect(native?.needsRosetta == false)

        // An Intel host must use the Intel helper even when both are present.
        let intelHost = EngineHelper.selection(bundle: anyBundle, isAppleSilicon: false)
        #expect(intelHost?.path == intel.path)
        #expect(intelHost?.needsRosetta == false)

        // Apple Silicon with only the Intel helper falls back and reports Rosetta.
        try fm.removeItem(at: arm)
        let fallback = EngineHelper.selection(bundle: anyBundle, isAppleSilicon: true)
        #expect(fallback?.path == intel.path)
        #expect(fallback?.needsRosetta == true)
    }

    @Test func decodesBothLibvmafMotionFormats() throws {
        // libvmaf 3.2.0 (the bundled engine) dropped `integer_motion`; the decoder must
        // still succeed and fall back to `integer_motion2`.
        let newFormat = "{\"frames\":[{\"frameNum\":0,\"metrics\":{\"vmaf\":67.5,\"integer_motion2\":1.5,\"integer_motion3\":1.9,\"integer_adm2\":0.93,\"integer_adm_scale0\":0.87,\"integer_adm_scale1\":0.91,\"integer_adm_scale2\":0.92,\"integer_adm_scale3\":0.97,\"integer_vif_scale0\":0.4,\"integer_vif_scale1\":0.6,\"integer_vif_scale2\":0.7,\"integer_vif_scale3\":0.8}}],\"pooled_metrics\":{\"vmaf\":{\"min\":58.9,\"max\":74.0,\"mean\":67.8,\"harmonic_mean\":67.7}},\"aggregate_metrics\":{}}"
        let decoded = try JSONDecoder().decode(
            VMAFCalculator.VMAFData.self,
            from: try #require(newFormat.data(using: .utf8)))
        let frame = try #require(decoded.frames.first)
        #expect(frame.vmafScore == 67.5)
        #expect(frame.integerMotion == 1.5) // legacy field now carries motion2
        #expect(frame.integerMotion2 == 1.5)

        // libvmaf 2.x output (older saved results) still decodes with the legacy key.
        let oldFormat = newFormat.replacingOccurrences(
            of: "\"integer_motion2\":1.5",
            with: "\"integer_motion\":2.5,\"integer_motion2\":1.5")
        let old = try JSONDecoder().decode(
            VMAFCalculator.VMAFData.self,
            from: try #require(oldFormat.data(using: .utf8)))
        #expect(old.frames.first?.integerMotion == 2.5)
    }

}
