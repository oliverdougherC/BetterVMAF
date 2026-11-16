//
//  VMAFTests.swift
//  VMAF
//
//  Created by Oliver Dougherty on 3/4/25.
//

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
