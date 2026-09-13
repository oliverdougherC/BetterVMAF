import Foundation

struct AnalysisEngine: Sendable {
    let directory: URL
    var ffmpeg: URL { directory.appendingPathComponent("ffmpeg") }
    var ffprobe: URL { directory.appendingPathComponent("ffprobe") }
    var models: URL { directory.appendingPathComponent("models") }
    static func bundled() throws -> Self {
        guard let resource = Bundle.main.resourceURL else { throw AnalysisError.engine("The bundled native engine is missing.") }
        let directory = resource.appendingPathComponent("engine")
        guard FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("ffmpeg").path),
              FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("ffprobe").path) else {
            throw AnalysisError.engine("The bundled native analysis engine is missing or not executable. Reinstall BetterVMAF; system helpers are never substituted.")
        }
        return Self(directory: directory)
    }
}

/// A single run's process, work directory, diagnostics and immutable input snapshot.
final class AnalysisService: @unchecked Sendable {
    let runner: OwnedProcess
    let engine: AnalysisEngine
    init(engine: AnalysisEngine, runner: OwnedProcess = OwnedProcess()) { self.engine = engine; self.runner = runner }
    func cancel() { runner.cancel() }

    func analyze(referenceURL: URL, comparisonURL: URL, configuration requestedConfiguration: AnalysisConfiguration,
                 progress: (@Sendable (AnalysisProgress) -> Void)? = nil,
                 diagnostic: (@Sendable (String, String, Int32?) -> Void)? = nil) async throws -> AnalysisResult {
        // This nonisolated async function runs off the main actor, including hashing and JSON parsing.
        var configuration = AnalysisConfiguration()
        configuration.viewingProfile = requestedConfiguration.viewingProfile
        configuration.threadCount = max(1, min(8, requestedConfiguration.threadCount))
        try Task.checkCancellation()
        let runID = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bettervmaf-\(runID.uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reference = try AnalysisFileIdentity.capture(referenceURL)
        let comparison = try AnalysisFileIdentity.capture(comparisonURL)
        let probe = AnalysisProbe(executable: engine.ffprobe, runner: runner)
        let sourceVideo = try await probe.read(referenceURL)
        let encodeVideo = try await probe.read(comparisonURL)
        let pairs = try AnalysisCorrespondence.validate(reference: sourceVideo, comparison: encodeVideo)
        let source = sourceVideo.stream, encode = encodeVideo.stream
        let totalDuration = pairs.reduce(0) { $0 + $1.duration }
        let actualFPS = Double(pairs.count) / totalDuration
        guard actualFPS >= 20, actualFPS <= 65 else {
            throw AnalysisError.invalid("This cadence is outside the tested 20–65 fps Standard/HFR model range.")
        }
        let hfr = actualFPS >= 45
        let modelName = configuration.viewingProfile.modelName(hfr: hfr)
        let model = engine.models.appendingPathComponent(modelName).appendingPathExtension("json")
        let modelHash = try AnalysisFileIdentity.hash(model)
        try FileManager.default.copyItem(at: model, to: directory.appendingPathComponent("model.json"))
        let normalizations = [Self.normalization(source), Self.normalization(encode)]
        let notes = try await correspondenceNotes(referenceURL: referenceURL, comparisonURL: comparisonURL, source: source, encode: encode, normalizations: normalizations, frameCount: pairs.count)
        let graph = Self.filterGraph(reference: source, comparison: encode, configuration: configuration)
        let arguments = ["-hide_banner", "-nostdin", "-loglevel", "info", "-nostats", "-progress", "pipe:1",
            "-filter_complex_threads", "\(max(1, min(8, configuration.threadCount)))", "-threads", "\(max(1, min(8, configuration.threadCount)))",
            "-noautorotate", "-i", referenceURL.path, "-threads", "\(max(1, min(8, configuration.threadCount)))", "-noautorotate", "-i", comparisonURL.path,
            "-filter_complex", graph, "-map", "[vmafout]", "-map", "[xpsnrout]", "-fps_mode", "passthrough", "-f", "null", "-"]
        let command = ([engine.ffmpeg.path] + arguments).map { String(reflecting: $0) }.joined(separator: " ")
        diagnostic?(command, "", nil)
        let relay = ProgressRelay(totalFrames: pairs.count, callback: progress)
        let budget = AnalysisLogBudget(files: [directory.appendingPathComponent("vmaf.json"), directory.appendingPathComponent("xpsnr.log")], onExceeded: { [runner] in runner.cancel() })
        defer { budget.stop() }
        let output: ProcessOutput
        do { output = try await runner.run(executable: engine.ffmpeg, arguments: arguments, directory: directory, onStdout: { relay.consume($0) }) }
        catch { if budget.exceeded { throw AnalysisError.invalid(AnalysisLimits.logLimitMessage) }; throw error }
        budget.check()
        guard !budget.exceeded else { throw AnalysisError.invalid(AnalysisLimits.logLimitMessage) }
        diagnostic?(command, output.stderr, output.status)
        guard output.status == 0 else { throw AnalysisError.process(output.status, output.stderr) }
        let log = try MetricLog.decode(Data(contentsOf: directory.appendingPathComponent("vmaf.json")), expectedCount: pairs.count)
        let xpsnr = try XPSNRLog.parse(stats: String(contentsOf: directory.appendingPathComponent("xpsnr.log"), encoding: .utf8), stderr: output.stderr, expectedCount: pairs.count)
        let cambiKey = "cambi_encbd_\(encode.bitDepth)_ench_\(encode.height)_encw_\(encode.width)_srch_\(source.height)_srcw_\(source.width)"
        var pooled = log.pooledMetrics
        for (id, value) in xpsnr.planeAverages { pooled[id] = ["native_average": value] }
        if let cambi = pooled[cambiKey] { pooled["cambi_encode"] = cambi }
        var aggregate = log.aggregateMetrics
        aggregate["xpsnr_min_plane"] = xpsnr.minimumPlaneAverage
        let samples = try log.frames.enumerated().map { index, frame in
            var values = frame.metrics
            for id in [cambiKey, "cambi_source", "cambi_full_reference"] {
                guard values[id]?.finiteValue != nil else { throw AnalysisError.missingMetric(id) }
            }
            values["cambi_encode"] = values[cambiKey]
            values.merge(xpsnr.frames[index]) { _, new in new }
            return AnalysisMetricSample(pair: pairs[index], values: values)
        }
        // End-to-end hashes prevent a changed file (including same-size edits) acquiring the old run's identity.
        guard try AnalysisFileIdentity.capture(referenceURL) == reference,
              try AnalysisFileIdentity.capture(comparisonURL) == comparison else {
            throw AnalysisError.invalid("An input changed during analysis. The result was discarded; retry with stable files.")
        }
        let versionOutput = try await runner.run(executable: engine.ffmpeg, arguments: ["-version"])
        guard versionOutput.status == 0 else { throw AnalysisError.process(versionOutput.status, versionOutput.stderr) }
        let version = String(decoding: versionOutput.stdout, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? "unknown"
        let definitions = Self.definitions(model: modelName, hash: modelHash, libraryVersion: log.version ?? "unknown", profile: configuration.viewingProfile)
        try Task.checkCancellation()
        return AnalysisResult(schemaVersion: 1, runID: runID, createdAt: Date(), reference: reference, comparison: comparison,
            referenceStream: source, comparisonStream: encode, configuration: configuration,
            engineVersion: "\(version); libvmaf \(log.version ?? "unknown")", engineSHA256: try AnalysisFileIdentity.hash(engine.ffmpeg),
            probeSHA256: try AnalysisFileIdentity.hash(engine.ffprobe), appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development",
            modelIdentifier: modelName, modelSHA256: modelHash, preprocessing: normalizations, correspondenceNotes: notes,
            definitions: definitions, samples: samples, pooledMetrics: pooled, aggregateMetrics: aggregate,
            comparedDuration: totalDuration, processingFPS: log.fps)
    }

    private func correspondenceNotes(referenceURL: URL, comparisonURL: URL, source: AnalysisStream, encode: AnalysisStream, normalizations: [String], frameCount: Int) async throws -> [String] {
        let referenceSignatures = try await signatures(referenceURL, stream: source, normalization: normalizations[0], expectedFrames: frameCount)
        let comparisonSignatures = try await signatures(comparisonURL, stream: encode, normalization: normalizations[1], expectedFrames: frameCount)
        return try AnalysisCorrespondence.validateSignatures(reference: referenceSignatures, comparison: comparisonSignatures, frameCount: frameCount)
    }

    private func signatures(_ url: URL, stream: AnalysisStream, normalization: String, expectedFrames: Int) async throws -> Data {
        let result = try await runner.run(executable: engine.ffmpeg, arguments: ["-v", "error", "-nostdin", "-threads", "2", "-noautorotate", "-i", url.path,
            "-map", "0:\(stream.index)", "-vf", normalization + ",scale=16:16:flags=area,format=gray",
            "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1"], stdoutLimit: min(256 * 1024 * 1024, max(256, expectedFrames * 256 + 256)))
        guard result.status == 0 else { throw AnalysisError.process(result.status, result.stderr) }
        return result.stdout
    }

    static func normalization(_ stream: AnalysisStream) -> String {
        let horizontalPosition = stream.chromaLocation == "center" ? 128 : 0
        return "scale=w=iw:h=ih:flags=bicubic+accurate_rnd+bitexact:in_range=\(stream.colorRange == "pc" ? "full" : "limited"):out_range=limited:in_color_matrix=bt709:out_color_matrix=bt709:in_h_chr_pos=\(horizontalPosition):in_v_chr_pos=128:out_h_chr_pos=0:out_v_chr_pos=128,format=yuv420p10le,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709"
    }

    static func filterGraph(reference: AnalysisStream, comparison: AnalysisStream, configuration: AnalysisConfiguration) -> String {
        let enc = "enc_width=\(comparison.width)\\:enc_height=\(comparison.height)\\:enc_bitdepth=\(comparison.bitDepth)"
        let model = "path=model.json\\:cambi.enc_width=\(comparison.width)\\:cambi.enc_height=\(comparison.height)\\:cambi.enc_bitdepth=\(comparison.bitDepth)"
        let cambi = "name=cambi\\:full_ref=true\\:\(enc)\\:src_width=\(reference.width)\\:src_height=\(reference.height)"
        let eof = "shortest=1:repeatlast=0:eof_action=endall:ts_sync_mode=nearest"
        // Both filters consume exactly the same normalized frames; XPSNR orientation differs intentionally.
        return "[0:\(reference.index)]\(normalization(reference)),settb=AVTB,setpts=PTS-STARTPTS,split=2[rv][rx];" +
            "[1:\(comparison.index)]\(normalization(comparison)),settb=AVTB,setpts=PTS-STARTPTS,split=2[dv][dx];" +
            "[dv][rv]libvmaf=model='\(model)':feature='\(cambi)':n_threads=\(max(1, min(8, configuration.threadCount))):log_fmt=json:log_path=vmaf.json:\(eof)[vmafout];" +
            "[rx][dx]xpsnr=stats_file=xpsnr.log:\(eof)[xpsnrout]"
    }

    static func definitions(model: String, hash: String, libraryVersion: String, profile: AnalysisConfiguration.ViewingProfile) -> [MetricDefinition] {
        var result = [MetricDefinition(id: "vmaf", name: "VMAF v1", version: "\(model); libvmaf \(libraryVersion)", modelSHA256: hash,
            direction: "higher", unit: "model score", nominalRange: [0, profile == .television4K3H ? 110 : 100], pooling: "libvmaf native arithmetic mean")]
        for plane in ["y", "u", "v"] {
            result.append(MetricDefinition(id: "xpsnr_\(plane)", name: "XPSNR \(plane.uppercased())", version: "FFmpeg pinned engine",
                modelSHA256: nil, direction: "higher", unit: "dB", nominalRange: nil, pooling: "FFmpeg native distortion-domain plane average; not arithmetic mean of frame dB"))
        }
        for (id, name) in [("cambi_encode", "Encode CAMBI"), ("cambi_source", "Source CAMBI"), ("cambi_full_reference", "Introduced CAMBI")] {
            result.append(MetricDefinition(id: id, name: name, version: "libvmaf \(libraryVersion)", modelSHA256: nil,
                direction: "lower", unit: "banding index", nominalRange: nil,
                pooling: id == "cambi_full_reference" ? "native mean of max(0, encode − source); diagnostic, not causal attribution" : "native arithmetic mean; BT.1886 EOTF"))
        }
        return result
    }
}

private final class ProgressRelay: @unchecked Sendable {
    private var parser = AnalysisProgressParser()
    let totalFrames: Int
    let callback: (@Sendable (AnalysisProgress) -> Void)?
    init(totalFrames: Int, callback: (@Sendable (AnalysisProgress) -> Void)?) { self.totalFrames = totalFrames; self.callback = callback }
    func consume(_ data: Data) { for update in parser.append(data, totalFrames: totalFrames) { callback?(update) } }
}
