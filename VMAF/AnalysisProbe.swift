import Foundation

struct DecodedFrame: Sendable, Equatable {
    let pts: Int64
    let time: Double
    let duration: Double
    let interlaced: Bool
}

struct ProbedVideo: Sendable {
    let stream: AnalysisStream
    let frames: [DecodedFrame]
}

struct AnalysisProbe {
    let executable: URL
    let runner: OwnedProcess

    func read(_ url: URL) async throws -> ProbedVideo {
        let metadata = try await runner.run(executable: executable, arguments: ["-v", "error", "-select_streams", "v",
            "-show_streams", "-of", "json", url.path])
        guard metadata.status == 0 else { throw AnalysisError.process(metadata.status, metadata.stderr) }
        let stream = try Self.decodeStream(metadata.stdout)
        let frameOutput = try await runner.run(executable: executable, arguments: ["-v", "error", "-select_streams", "v:0",
            "-show_frames", "-show_entries", "frame=best_effort_timestamp,duration,pkt_duration,interlaced_frame",
            "-of", "compact=p=0", url.path])
        guard frameOutput.status == 0 else { throw AnalysisError.process(frameOutput.status, frameOutput.stderr) }
        let frames = try Self.decodeFrames(frameOutput.stdout, timeBase: stream.timeBase)
        return ProbedVideo(stream: stream, frames: frames)
    }

    static func rational(_ text: String) -> Double? {
        let parts = text.split(separator: "/")
        guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator > 0,
              numerator.isFinite, denominator.isFinite else { return nil }
        return numerator / denominator
    }

    static func decodeStream(_ data: Data) throws -> AnalysisStream {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = root["streams"] as? [[String: Any]], streams.count == 1, let raw = streams.first,
              let width = raw["width"] as? Int, let height = raw["height"] as? Int, width > 0, height > 0 else {
            throw AnalysisError.invalid("No unambiguous primary video stream was decoded.")
        }
        guard (raw["disposition"] as? [String: Any])?["attached_pic"] as? Int != 1 else {
            throw AnalysisError.invalid("Attached artwork is not a supported primary video stream.")
        }
        func string(_ key: String, _ fallback: String = "unknown") -> String { raw[key] as? String ?? fallback }
        let format = string("pix_fmt")
        let bitDepth: Int
        if ["yuv420p", "yuvj420p"].contains(format) { bitDepth = 8 }
        else if format == "yuv420p10le" { bitDepth = 10 }
        else { bitDepth = Int(string("bits_per_raw_sample")) ?? 0 }
        let sideData = raw["side_data_list"] as? [[String: Any]] ?? []
        let rotation = sideData.compactMap { $0["rotation"] as? Double }.first ?? 0
        return AnalysisStream(index: raw["index"] as? Int ?? 0, codec: string("codec_name"), width: width, height: height,
            pixelFormat: format, bitDepth: bitDepth, timeBase: string("time_base"), averageFrameRate: string("avg_frame_rate"),
            sampleAspectRatio: string("sample_aspect_ratio"), rotation: rotation, fieldOrder: string("field_order"),
            colorMatrix: string("color_space"), colorPrimaries: string("color_primaries"), colorTransfer: string("color_transfer"),
            colorRange: string("color_range"), chromaLocation: string("chroma_location"), duration: Double(string("duration")))
    }

    static func decodeFrames(_ data: Data, timeBase: String) throws -> [DecodedFrame] {
        guard let scale = rational(timeBase), scale > 0 else { throw AnalysisError.invalid("Invalid decoded stream time base.") }
        var rows: [(Int64, Int64?, Bool)] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            var fields: [String: String] = [:]
            for part in line.split(separator: "|") {
                let pair = part.split(separator: "=", maxSplits: 1)
                if pair.count == 2 { fields[String(pair[0])] = String(pair[1]) }
            }
            // Side-data records do not describe additional decoded frames.
            guard let text = fields["best_effort_timestamp"] else {
                if fields["interlaced_frame"] != nil { throw AnalysisError.invalid("A decoded frame has no authoritative presentation timestamp.") }
                continue
            }
            guard let pts = Int64(text) else { throw AnalysisError.invalid("A decoded frame has no authoritative presentation timestamp.") }
            guard rows.count < AnalysisLimits.maximumFrames else { throw AnalysisError.invalid(AnalysisLimits.frameLimitMessage) }
            rows.append((pts, Int64(fields["duration"] ?? fields["pkt_duration"] ?? ""), fields["interlaced_frame"] == "1"))
        }
        guard !rows.isEmpty else { throw AnalysisError.invalid("No decoded video frames were found.") }
        return try rows.enumerated().map { index, row in
            if index > 0, row.0 <= rows[index - 1].0 { throw AnalysisError.invalid("Non-increasing presentation timestamps are unsupported.") }
            let durationTicks: Int64
            if index + 1 < rows.count { durationTicks = rows[index + 1].0 - row.0 }
            else if let declared = row.1, declared > 0 { durationTicks = declared }
            else { throw AnalysisError.invalid("The last decoded frame has no duration; compared coverage cannot be established.") }
            guard durationTicks > 0 else { throw AnalysisError.invalid("Invalid decoded frame duration.") }
            return DecodedFrame(pts: row.0, time: Double(row.0) * scale, duration: Double(durationTicks) * scale, interlaced: row.2)
        }
    }
}

enum AnalysisCorrespondence {
    static func validate(reference: ProbedVideo, comparison: ProbedVideo) throws -> [AnalysisFramePair] {
        for video in [reference, comparison] { try validateStream(video) }
        let a = reference.stream, b = comparison.stream
        guard (320...7680).contains(a.width), (200...4320).contains(a.height), (180...7680).contains(b.width), (150...7680).contains(b.height) else {
            throw AnalysisError.invalid("Original dimensions are outside the native CAMBI supported range (source at least 320×200; encode at least 180×150).")
        }
        guard a.width == b.width, a.height == b.height else {
            throw AnalysisError.invalid("The source and encode must use the same pixel dimensions. Scaling comparisons require an explicit viewing canvas and are not enabled yet.")
        }
        guard reference.frames.count == comparison.frames.count else {
            throw AnalysisError.invalid("Decoded frame counts differ (\(reference.frames.count) versus \(comparison.frames.count)). Drops, additions and unequal duration are not valid Standard comparisons.")
        }
        let smallestFrame = min(reference.frames.lazy.map(\.duration).min() ?? 0, comparison.frames.lazy.map(\.duration).min() ?? 0)
        let tolerance = max(0.000002, min(smallestFrame * 0.2, max(AnalysisProbe.rational(a.timeBase) ?? 0, AnalysisProbe.rational(b.timeBase) ?? 0) * 1.1))
        guard let referenceStart = reference.frames.first?.time, let comparisonStart = comparison.frames.first?.time else {
            throw AnalysisError.invalid("No frame pairs are available.")
        }
        // Require the same start rather than silently erasing an unexplained offset.
        guard abs(referenceStart - comparisonStart) <= tolerance else {
            throw AnalysisError.invalid("Video start timestamps differ. Explicit offset alignment is not enabled; re-export a matching time range.")
        }
        return try zip(reference.frames, comparison.frames).enumerated().map { index, frames in
            let r = frames.0, c = frames.1
            guard abs(r.time - c.time) <= tolerance, abs(r.duration - c.duration) <= tolerance else {
                throw AnalysisError.invalid("Frame correspondence differs at frame \(index) (timestamp or duration). Cadence conversion, drops and retiming are unsupported.")
            }
            return AnalysisFramePair(index: index, referencePTS: r.pts, comparisonPTS: c.pts,
                referenceTimeBase: a.timeBase, comparisonTimeBase: b.timeBase,
                referenceTimestamp: r.time, comparisonTimestamp: c.time,
                timestamp: r.time - referenceStart, duration: r.duration)
        }
    }

    static func validateStream(_ video: ProbedVideo) throws {
        let stream = video.stream
        guard !["smpte2084", "arib-std-b67"].contains(stream.colorTransfer) else {
            throw AnalysisError.invalid("PQ/HLG HDR is outside Standard's validated SDR measurement path. No tone mapping or HDR quality score was applied.")
        }
        guard stream.colorMatrix == "bt709", stream.colorPrimaries == "bt709", stream.colorTransfer == "bt709" else {
            throw AnalysisError.invalid("Standard requires explicitly tagged BT.709 SDR matrix, primaries and transfer. Correct missing or unsupported color metadata before comparing.")
        }
        guard ["tv", "pc"].contains(stream.colorRange), ["left", "center"].contains(stream.chromaLocation) else {
            throw AnalysisError.invalid("Standard requires explicit full/limited range and left/center chroma location metadata.")
        }
        guard ["yuv420p", "yuvj420p", "yuv420p10le"].contains(stream.pixelFormat) else {
            throw AnalysisError.invalid("Standard currently supports 8/10-bit 4:2:0 YUV SDR inputs. This pixel format is unsupported: \(stream.pixelFormat).")
        }
        guard ["1:1", "1/1"].contains(stream.sampleAspectRatio), abs(stream.rotation) < 0.001,
              !video.frames.contains(where: \.interlaced), ["progressive", "unknown"].contains(stream.fieldOrder) else {
            throw AnalysisError.invalid("Standard requires square pixels, zero rotation and progressive frames. Geometry/interlace normalization is not silently applied.")
        }
    }

    /// Low-resolution luminance correspondence screen, not a quality metric or proof of scene identity.
    /// Refuses strong evidence of a nearby shifted/dropped/repeated frame, while leaving distortion visible.
    static func validateSignatures(reference: Data, comparison: Data, frameCount: Int, width: Int = 16) throws -> [String] {
        let stride = width * width
        guard reference.count == frameCount * stride, comparison.count == frameCount * stride else {
            throw AnalysisError.invalid("Content-screen decode coverage differs from the authoritative frame map.")
        }
        return try reference.withUnsafeBytes { (ref: UnsafeRawBufferPointer) in
        try comparison.withUnsafeBytes { (cmp: UnsafeRawBufferPointer) in
        func error(_ r: Int, _ c: Int) -> Double {
            var sum = 0
            for pixel in 0..<stride { sum += abs(Int(ref[r * stride + pixel]) - Int(cmp[c * stride + pixel])) }
            return Double(sum) / Double(stride)
        }
        var totalError = 0.0
        for i in 0..<frameCount {
            if i % 512 == 0 { try Task.checkCancellation() }
            let aligned = error(i, i)
            totalError += aligned
            if i > 0 {
                var encodeChange = 0, sourceChange = 0
                for pixel in 0..<stride {
                    encodeChange += abs(Int(cmp[i * stride + pixel]) - Int(cmp[(i - 1) * stride + pixel]))
                    sourceChange += abs(Int(ref[i * stride + pixel]) - Int(ref[(i - 1) * stride + pixel]))
                }
                if Double(encodeChange) / Double(stride) < 0.15, Double(sourceChange) / Double(stride) > 1.5, aligned > 1.5 {
                    throw AnalysisError.invalid("Encode frame \(i) repeats while the source changes. Possible freeze or duplicated frame; Standard refused a misleading quality verdict.")
                }
            }
            guard aligned > 0.5 else { continue }
            for offset in [-2, -1, 1, 2] where i + offset >= 0 && i + offset < frameCount {
                let alternative = error(i + offset, i)
                if alternative < aligned * 0.3, aligned - alternative > 0.5 {
                    throw AnalysisError.invalid("Content at frame \(i) matches source frame \(i + offset) substantially better. Possible shift, drop or repeat; Standard refused a misleading quality verdict.")
                }
            }
        }
        guard totalError / Double(max(1, frameCount)) < 64 else {
            throw AnalysisError.invalid("Source and encode content could not be matched confidently. Verify the same source, edit, crop and time range.")
        }
        return ["All decoded timestamps and frame durations matched; no padding or dropped frame was accepted.",
                "16×16 luma screening found no strong ±2-frame displacement. This conservative screen is not proof of semantic identity; static/repetitive scenes and severe distortions can be ambiguous."]
        }
        }
    }
}
