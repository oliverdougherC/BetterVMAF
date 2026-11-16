//
//  EngineHelper.swift
//  VMAF
//
//  Selects the bundled FFmpeg that matches the host CPU.
//

import Foundation

/// Locates the bundled FFmpeg engine for the machine Better VMAF is running on.
///
/// Releases ship two thin binaries: `ffmpeg` (arm64) and `ffmpeg.x86_64`.
/// Launching the Intel build on Apple Silicon translates the whole analysis
/// through Rosetta, which Apple removes in macOS 28, so an Apple Silicon host
/// must prefer the arm64 helper and reach for the Intel build only when the
/// native one is missing from the bundle.
enum EngineHelper {
    static let armResourceName = "ffmpeg"
    static let intelResourceName = "ffmpeg.x86_64"
    static let fallbackSystemPath = "/opt/homebrew/bin/ffmpeg"

    struct Selection: Equatable {
        let path: String
        /// True when the chosen binary needs Rosetta on this host.
        let needsRosetta: Bool
    }

    static func isAppleSiliconHost() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else {
            // No answer from the kernel: trust the slice the app is running.
            #if arch(arm64)
            return true
            #else
            return false
            #endif
        }
        return value == 1
    }

    /// Bundle resource names in the order they may be launched on this host.
    static func candidateOrder(isAppleSilicon: Bool) -> [String] {
        isAppleSilicon ? [armResourceName, intelResourceName] : [intelResourceName]
    }

    static func selection(bundle: Bundle, isAppleSilicon: Bool) -> Selection? {
        let fileManager = FileManager.default
        guard let resourceURL = bundle.resourceURL else { return nil }
        for name in candidateOrder(isAppleSilicon: isAppleSilicon) {
            // Xcode flattens these into Contents/Resources, so resolve directly
            // instead of Bundle.path(forResource:) (which caches its map at init).
            // A sandboxed app cannot chmod bundle resources, so permissions are
            // fixed when the helper is checked in and verified by CI.
            let candidate = resourceURL.appendingPathComponent(name)
            guard let attributes = try? fileManager.attributesOfItem(atPath: candidate.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  let permissions = attributes[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o111 != 0 else { continue }
            return Selection(path: candidate.path, needsRosetta: isAppleSilicon && name == intelResourceName)
        }
        return nil
    }

    static func resolvePath(bundle: Bundle = .main) -> String? {
        let isAppleSilicon = isAppleSiliconHost()
        guard let selection = selection(bundle: bundle, isAppleSilicon: isAppleSilicon) else { return nil }
        if selection.needsRosetta {
            NSLog("Better VMAF: bundled arm64 FFmpeg is unavailable; the Intel helper runs under Rosetta, which ends at macOS 28.")
        }
        return selection.path
    }
}
