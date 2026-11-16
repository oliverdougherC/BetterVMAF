//
//  EngineHelper.swift
//  VMAF
//
//  Selects the bundled FFmpeg that matches the host CPU.
//

import Foundation

/// Locates the bundled FFmpeg engine for the machine Better VMAF is running on.
///
/// Releases ship one thin helper per architecture: `ffmpeg` is arm64 and
/// `ffmpeg.x86_64` is Intel. A host never launches the other architecture's
/// helper — running the Intel build on Apple Silicon translates the entire
/// analysis through Rosetta, which Apple removes in macOS 28. A missing or
/// mismatched native helper is therefore a packaging error to report, not
/// something to paper over by borrowing the foreign binary.
enum EngineHelper {
    static let armResourceName = "ffmpeg"
    static let intelResourceName = "ffmpeg.x86_64"
    /// Development-only fallback for running from a checkout without built
    /// bundle resources (Homebrew supplies an arm64 engine on Apple Silicon).
    static let fallbackSystemPath = "/opt/homebrew/bin/ffmpeg"

    enum Problem: Error, Equatable {
        /// The bundle exposes no resource directory.
        case bundleResourcesMissing
        /// The helper file for this architecture is absent from the bundle.
        case helperMissing
        /// The helper exists but has no executable bit (damaged install).
        case helperNotExecutable
        /// The helper exists and is executable but its Mach-O header lacks the
        /// required CPU slice (wrong file shipped, e.g. Intel helper under the
        /// arm64 name).
        case helperArchitectureMismatch(found: [String])
    }

    enum Availability: Equatable {
        case bundled(path: String)
        /// No bundled helper at all; a system-installed engine may run instead.
        case systemFallback(path: String)
        case unavailable(Problem)
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

    /// The bundle resource name for this architecture — never the foreign helper.
    static func resourceName(isAppleSilicon: Bool) -> String {
        isAppleSilicon ? armResourceName : intelResourceName
    }

    /// CPU types recorded in Mach-O headers (thin or fat) read from `url`
    /// without spawning a process. Unknown formats report no types.
    static func declaredMachOCPUTypes(at url: URL) -> [String] {
        // CPU_TYPE_* from <mach/machine.h>.
        func name(for type: UInt32) -> String {
            switch type {
            case 0x0100_000C: return "arm64"
            case 0x0100_0007: return "x86_64"
            case 0x0000_000C: return "arm64_32"
            case 0x0000_0007: return "x86"
            default: return String(format: "cpu-0x%08X", type)
            }
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 8 else { return [] }
        func byte(_ i: Int) -> UInt8 { data[data.index(data.startIndex, offsetBy: i)] }
        func u32le(_ i: Int) -> UInt32 { UInt32(byte(i)) | (UInt32(byte(i + 1)) << 8) | (UInt32(byte(i + 2)) << 16) | (UInt32(byte(i + 3)) << 24) }
        func u32be(_ i: Int) -> UInt32 { (UInt32(byte(i)) << 24) | (UInt32(byte(i + 1)) << 16) | (UInt32(byte(i + 2)) << 8) | UInt32(byte(i + 3)) }
        switch [byte(0), byte(1), byte(2), byte(3)] {
        case [0xCF, 0xFA, 0xED, 0xFE]: // MH_MAGIC_64, little-endian header
            return [name(for: u32le(4))]
        case [0xFE, 0xED, 0xFA, 0xCF]: // MH_MAGIC_64, big-endian header
            return [name(for: u32be(4))]
        case [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA]: // FAT binary
            let bigEndian = byte(0) == 0xCA
            let read: (Int) -> UInt32 = bigEndian ? u32be : u32le
            let count = Int(read(4))
            guard count >= 1, count <= 16, data.count >= 8 + count &* 20 else { return [] }
            return (0..<count).map { name(for: read(8 + $0 * 20)) }
        default:
            return []
        }
    }

    /// Validates the helper for this host architecture. A helper that exists
    /// but is wrong (permissions, architecture) is a hard failure: only a
    /// completely absent helper may reach the development system fallback.
    static func availability(
        bundle: Bundle,
        isAppleSilicon: Bool,
        systemFallbackPath: String = fallbackSystemPath,
        fileManager: FileManager = .default
    ) -> Availability {
        guard let resourceURL = bundle.resourceURL else {
            return .unavailable(.bundleResourcesMissing)
        }
        // Xcode flattens resources into Contents/Resources, so resolve directly
        // instead of Bundle.path(forResource:) (which caches its map at init).
        // A sandboxed app cannot chmod bundle resources, so permissions are
        // fixed when the helper is checked in and verified by CI.
        let candidate = resourceURL.appendingPathComponent(resourceName(isAppleSilicon: isAppleSilicon))
        guard let attributes = try? fileManager.attributesOfItem(atPath: candidate.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular else {
            // Only a *built-from-source* checkout legitimately lacks bundle
            // resources. In a shipped app this state is a packaging error, so
            // restrict the fallback to non-bundle hosts.
            if bundle.bundleURL.pathExtension != "app",
               fileManager.isExecutableFile(atPath: systemFallbackPath) {
                return .systemFallback(path: systemFallbackPath)
            }
            return .unavailable(.helperMissing)
        }
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o111 != 0 else {
            return .unavailable(.helperNotExecutable)
        }
        let required = isAppleSilicon ? "arm64" : "x86_64"
        let declared = declaredMachOCPUTypes(at: candidate)
        guard declared.contains(required) else {
            return .unavailable(.helperArchitectureMismatch(found: declared))
        }
        return .bundled(path: candidate.path)
    }

    static func resolve(bundle: Bundle = .main) -> Availability {
        let isAppleSilicon = isAppleSiliconHost()
        return availability(bundle: bundle, isAppleSilicon: isAppleSilicon)
    }
}

extension EngineHelper.Problem: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .bundleResourcesMissing:
            return "Better VMAF could not read its application bundle."
        case .helperMissing:
            return "The bundled FFmpeg engine for this Mac is missing. Reinstall Better VMAF from a package built for this Mac."
        case .helperNotExecutable:
            return "The bundled FFmpeg engine is not executable. Reinstall Better VMAF."
        case .helperArchitectureMismatch(let found):
            // Never fall back to the Intel helper on Apple Silicon: it would run
            // the whole analysis under Rosetta, which ends at macOS 28.
            let foundText = found.isEmpty ? "no recognized Mach-O architecture" : found.joined(separator: ", ")
            return "The bundled FFmpeg engine does not match this Mac (\(foundText) instead of the native architecture). Reinstall Better VMAF from a package built for this Mac."
        }
    }
}
