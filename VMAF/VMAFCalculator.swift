//
//  VMAFCalculator.swift
//  VMAF
//
//  Created by Oliver Dougherty on 3/4/25.
//


import Foundation
import AVFoundation
import Charts

class VMAFCalculator {
    struct VMAFResult {
        let score: Double
        let minScore: Double
        let maxScore: Double
        let harmonicMean: Double
        let frameMetrics: [FrameMetric]
        let duration: TimeInterval
        let frameCount: Int
        /// libvmaf identity that produced these values, for export provenance.
        var libvmafVersion: String? = nil
    }
    
    // Add delegate for progress updates
    protocol VMAFCalculatorDelegate {
        func vmafCalculatorDidUpdateProgress(frameCount: Int, fps: Double, progress: Double, totalFrames: Int)
    }
    
    var delegate: VMAFCalculatorDelegate?
    private var lastCommand: String = ""
    private var lastErrorOutput: String = ""
    private var lastTerminationStatus: Int32?
    private var estimatedTotalFrames: Int = 0
    
    struct FrameMetric: Codable, Identifiable {
        let frameNumber: Int
        let vmafScore: Double
        /// libvmaf 2.x `integer_motion`. Nil when the engine did not report it.
        let integerMotion: Double?
        /// libvmaf 3.x `integer_motion2`. A different feature from
        /// `integer_motion`, so the two identities are kept apart rather than
        /// collapsed into one field.
        let integerMotion2: Double?
        let integerAdm2: Double
        let integerAdmScales: [Double]
        let integerVifScales: [Double]

        // Identifiable conformance
        var id: Int { frameNumber }

        /// The motion reading to display, with the libvmaf feature name it came
        /// from. Prefer the legacy identity when the engine reported it.
        var motionReading: (feature: String, value: Double)? {
            if let integerMotion { return ("integer_motion", integerMotion) }
            if let integerMotion2 { return ("integer_motion2", integerMotion2) }
            return nil
        }
        
        // Computed property for timestamp (assuming 30fps)
        var timestamp: TimeInterval {
            TimeInterval(frameNumber - 1) / 30.0
        }
        
        init(frameNumber: Int,
             vmafScore: Double,
             integerMotion: Double?,
             integerMotion2: Double?,
             integerAdm2: Double,
             integerAdmScales: [Double],
             integerVifScales: [Double]) {
            self.frameNumber = frameNumber
            self.vmafScore = vmafScore
            self.integerMotion = integerMotion
            self.integerMotion2 = integerMotion2
            self.integerAdm2 = integerAdm2
            self.integerAdmScales = integerAdmScales
            self.integerVifScales = integerVifScales
        }
        
        enum CodingKeys: String, CodingKey {
            case frameNumber = "frameNum"
            case metrics
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            frameNumber = try container.decode(Int.self, forKey: .frameNumber)
            
            let metricsContainer = try container.nestedContainer(keyedBy: MetricsCodingKeys.self, forKey: .metrics)
            vmafScore = try metricsContainer.decode(Double.self, forKey: .vmaf)
            // libvmaf 2.x emits `integer_motion`; libvmaf 3.2.0 replaced it with
            // `integer_motion2`/`integer_motion3`. Each identity is stored in its
            // own optional so a value is never recorded under a feature the engine
            // did not report. VMAF itself is unaffected.
            integerMotion = try metricsContainer.decodeIfPresent(Double.self, forKey: .integerMotion)
            integerMotion2 = try metricsContainer.decodeIfPresent(Double.self, forKey: .integerMotion2)
            integerAdm2 = try metricsContainer.decode(Double.self, forKey: .integerAdm2)
            
            integerAdmScales = [
                try metricsContainer.decode(Double.self, forKey: .integerAdmScale0),
                try metricsContainer.decode(Double.self, forKey: .integerAdmScale1),
                try metricsContainer.decode(Double.self, forKey: .integerAdmScale2),
                try metricsContainer.decode(Double.self, forKey: .integerAdmScale3)
            ]
            
            integerVifScales = [
                try metricsContainer.decode(Double.self, forKey: .integerVifScale0),
                try metricsContainer.decode(Double.self, forKey: .integerVifScale1),
                try metricsContainer.decode(Double.self, forKey: .integerVifScale2),
                try metricsContainer.decode(Double.self, forKey: .integerVifScale3)
            ]
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(frameNumber, forKey: .frameNumber)
            
            var metricsContainer = container.nestedContainer(keyedBy: MetricsCodingKeys.self, forKey: .metrics)
            try metricsContainer.encode(vmafScore, forKey: .vmaf)
            // Round-trip preserves identity: a libvmaf 3.x reading is re-emitted
            // as `integer_motion2`, never resurrected under the legacy name.
            try metricsContainer.encodeIfPresent(integerMotion, forKey: .integerMotion)
            try metricsContainer.encodeIfPresent(integerMotion2, forKey: .integerMotion2)
            try metricsContainer.encode(integerAdm2, forKey: .integerAdm2)
            
            try metricsContainer.encode(integerAdmScales[0], forKey: .integerAdmScale0)
            try metricsContainer.encode(integerAdmScales[1], forKey: .integerAdmScale1)
            try metricsContainer.encode(integerAdmScales[2], forKey: .integerAdmScale2)
            try metricsContainer.encode(integerAdmScales[3], forKey: .integerAdmScale3)
            
            try metricsContainer.encode(integerVifScales[0], forKey: .integerVifScale0)
            try metricsContainer.encode(integerVifScales[1], forKey: .integerVifScale1)
            try metricsContainer.encode(integerVifScales[2], forKey: .integerVifScale2)
            try metricsContainer.encode(integerVifScales[3], forKey: .integerVifScale3)
        }
        
        private enum MetricsCodingKeys: String, CodingKey {
            case vmaf
            case integerMotion = "integer_motion"
            case integerMotion2 = "integer_motion2"
            case integerAdm2 = "integer_adm2"
            case integerAdmScale0 = "integer_adm_scale0"
            case integerAdmScale1 = "integer_adm_scale1"
            case integerAdmScale2 = "integer_adm_scale2"
            case integerAdmScale3 = "integer_adm_scale3"
            case integerVifScale0 = "integer_vif_scale0"
            case integerVifScale1 = "integer_vif_scale1"
            case integerVifScale2 = "integer_vif_scale2"
            case integerVifScale3 = "integer_vif_scale3"
        }
    }
    
    struct VMAFMetrics: Codable {
        let min: Double
        let max: Double
        let mean: Double
        let harmonicMean: Double
        
        enum CodingKeys: String, CodingKey {
            case min
            case max
            case mean
            case harmonicMean = "harmonic_mean"
        }
    }
    
    struct VMAFData: Codable {
        let frames: [FrameMetric]
        let pooledMetrics: [String: VMAFMetrics]
        let aggregateMetrics: [String: String]
        /// libvmaf reports its version at the top level of the JSON log; newer
        /// builds emit `3.2.0`, older ones a git hash. Kept so each result
        /// records which feature identities it may contain.
        let libvmafVersion: String?

        enum CodingKeys: String, CodingKey {
            case frames
            case pooledMetrics = "pooled_metrics"
            case aggregateMetrics = "aggregate_metrics"
            case libvmafVersion = "version"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            frames = try container.decode([FrameMetric].self, forKey: .frames)
            pooledMetrics = try container.decode([String: VMAFMetrics].self, forKey: .pooledMetrics)
            aggregateMetrics = try container.decode([String: String].self, forKey: .aggregateMetrics)
            libvmafVersion = try container.decodeIfPresent(String.self, forKey: .libvmafVersion)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(frames, forKey: .frames)
            try container.encode(pooledMetrics, forKey: .pooledMetrics)
            try container.encode(aggregateMetrics, forKey: .aggregateMetrics)
            try container.encodeIfPresent(libvmafVersion, forKey: .libvmafVersion)
        }
    }
    
    private let engine: EngineHelper.Availability

    /// Path for launching, or the typed packaging problem. A missing native
    /// helper must not fall back to the foreign-architecture helper: that would
    /// run every frame through Rosetta, which ends at macOS 28.
    private var ffmpegPath: String {
        get throws {
            switch engine {
            case .bundled(let path), .systemFallback(let path):
                return path
            case .unavailable(let problem):
                throw VMAFError.engineUnavailable(problem)
            }
        }
    }
    
    // Determine the resolution of a video to validate inputs and choose the right model.
    private func videoResolution(for url: URL) async throws -> (width: Int, height: Int) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw VMAFError.missingVideoTrack
        }
        
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformedSize = naturalSize.applying(transform)
        let width = Int(round(abs(transformedSize.width)))
        let height = Int(round(abs(transformedSize.height)))
        return (width: width, height: height)
    }
    
    // Pick the matching VMAF model name based on resolution (defaults to 1080p model).
    private func modelName(for resolution: (width: Int, height: Int)) -> String {
        let longestSide = max(resolution.width, resolution.height)
        return longestSide >= 2160 ? "vmaf_4k_v0.6.1" : "vmaf_v0.6.1"
    }
    
    // Escape paths for use inside an ffmpeg filter string.
    private func escapeForFFmpegFilter(_ path: String) -> String {
        var escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: ":", with: "\\:")
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        escaped = escaped.replacingOccurrences(of: " ", with: "\\ ")
        return escaped
    }
    
    // Resolve the on-disk model path inside the app bundle.
    private func modelPath(for resolution: (width: Int, height: Int)) throws -> String {
        let name = modelName(for: resolution)
        let fm = FileManager.default
        
        // Preferred location: Resources/Models/<name>.json
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Models"),
           fm.fileExists(atPath: url.path) {
            return url.path
        }
        
        // Fallback: Resource root
        if let url = Bundle.main.url(forResource: name, withExtension: "json"),
           fm.fileExists(atPath: url.path) {
            return url.path
        }
        
        // Dev fallback: relative to working directory if running from Xcode without copy phase
        let workingPath = "VMAF/Resources/Models/\(name).json"
        if fm.fileExists(atPath: workingPath) {
            return URL(fileURLWithPath: workingPath).path
        }
        
        throw VMAFError.modelNotFound(name)
    }
    
    // Estimate frame count based on duration and nominal frame rate.
    private func estimateFrameCount(for url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        guard let duration = try? await asset.load(.duration) else { return nil }
        guard let fps = try? await track.load(.nominalFrameRate) else { return nil }
        
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0, fps > 0 else { return nil }
        return Int(round(durationSeconds * Double(fps)))
    }
    
    func getEstimatedTotalFrames() -> Int? {
        estimatedTotalFrames > 0 ? estimatedTotalFrames : nil
    }
    
    init() {
        engine = EngineHelper.resolve(bundle: .main)
        switch engine {
        case .bundled(let path), .systemFallback(let path):
            print("Using ffmpeg at path: \(path)")
        case .unavailable(let problem):
            NSLog("Better VMAF: no usable bundled FFmpeg engine: \(problem.localizedDescription)")
        }
    }
    
    func calculateVMAF(referenceVideo: URL, comparisonVideo: URL) async throws -> VMAFResult {
        let referenceResolution = try await videoResolution(for: referenceVideo)
        let comparisonResolution = try await videoResolution(for: comparisonVideo)
        
        guard referenceResolution == comparisonResolution else {
            throw VMAFError.resolutionMismatch(
                referenceWidth: referenceResolution.width,
                referenceHeight: referenceResolution.height,
                comparisonWidth: comparisonResolution.width,
                comparisonHeight: comparisonResolution.height
            )
        }
        
        let selectedModelPath = try modelPath(for: referenceResolution)
        let escapedModelPath = escapeForFFmpegFilter(selectedModelPath)
        lastErrorOutput = ""
        lastTerminationStatus = nil
        estimatedTotalFrames = 0
        
        let refFrames = await estimateFrameCount(for: referenceVideo) ?? 0
        let cmpFrames = await estimateFrameCount(for: comparisonVideo) ?? 0
        let nonZeroEstimates = [refFrames, cmpFrames].filter { $0 > 0 }
        if let minEstimate = nonZeroEstimates.min() {
            estimatedTotalFrames = minEstimate
        }
        
        // Create a temporary file for the VMAF JSON log
        let tempDir = FileManager.default.temporaryDirectory
        let logFile = tempDir.appendingPathComponent(UUID().uuidString + ".json")
        
        // Ensure the temporary directory exists and is writable
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let escapedLogPath = escapeForFFmpegFilter(logFile.path)
        // libvmaf 3.x expects model=path=... rather than model_path=...
        let lavfiFilterGraph = "[1:v]setpts=PTS-STARTPTS[dist];[0:v]setpts=PTS-STARTPTS[ref];[dist][ref]libvmaf=model=path=\(escapedModelPath):log_fmt=json:log_path=\(escapedLogPath):n_threads=99"
        
        
        // Build the ffmpeg command with enhanced metrics collection
        let command = [
            try ffmpegPath,
            "-hide_banner",
            "-loglevel", "info",
            "-i", referenceVideo.path,
            "-i", comparisonVideo.path,
            "-lavfi", lavfiFilterGraph,
            "-f", "null",
            "-"
        ]
        
        // Store the command for later display
        lastCommand = command.joined(separator: " ")
        
        print("Running FFmpeg command: \(lastCommand)")
        
        // Run the command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        
        // Set up environment variables to ensure we use bundled libraries
        var env = ProcessInfo.processInfo.environment
        if let resourcePath = Bundle.main.resourcePath {
            print("Setting up environment variables:")
            print("  Resource path: \(resourcePath)")
            
            // Set DYLD_LIBRARY_PATH to look in the app bundle first
            let libraryPath = "\(resourcePath)"
            print("  Setting DYLD_LIBRARY_PATH: \(libraryPath)")
            env["DYLD_LIBRARY_PATH"] = libraryPath
            
            // Set DYLD_FALLBACK_LIBRARY_PATH as a backup
            env["DYLD_FALLBACK_LIBRARY_PATH"] = "/usr/lib:/usr/local/lib:/opt/homebrew/lib"
            
            // Set DYLD_FRAMEWORK_PATH
            env["DYLD_FRAMEWORK_PATH"] = resourcePath
        }
        process.environment = env
        
        // Check if we can run ffmpeg directly or need to use a helper shell
        if !FileManager.default.isExecutableFile(atPath: command[0]) {
            // If ffmpeg is not executable directly, try using bash to execute it
            print("ffmpeg not directly executable, trying via /bin/sh")
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command.joined(separator: " ")]
        }
        
        let outputPipe = Pipe()
        process.standardError = outputPipe
        process.standardOutput = outputPipe
        
        // Collect combined stdout/stderr, and parse progress as chunks arrive.
        let fileHandle = outputPipe.fileHandleForReading
        let outputQueue = DispatchQueue(label: "ffmpeg-output-buffer")
        var collectedData = Data()
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            outputQueue.async {
                collectedData.append(data)
            }
            if let output = String(data: data, encoding: .utf8) {
                self?.parseFFmpegOutput(output)
            }
        }
        
        do {
            try process.run()
            
            // Wait for process to complete
            process.waitUntilExit()
            lastTerminationStatus = process.terminationStatus
            
            // Stop readability handler
            fileHandle.readabilityHandler = nil
            
            // Capture all output that was collected
            let dataSnapshot: Data = outputQueue.sync { collectedData }
            let errorString = String(data: dataSnapshot, encoding: .utf8) ?? "Unknown error"
            lastErrorOutput = errorString
            print("FFmpeg output: \(errorString)")
            
            // Check if process failed
            if process.terminationStatus != 0 {
                print("FFmpeg failed with status: \(process.terminationStatus)")
                
                // Provide more detailed error information
                var errorMessage = !errorString.isEmpty ? errorString : "FFmpeg exited with status: \(process.terminationStatus)"
                
                if errorString.isEmpty {
                    errorMessage = "FFmpeg exited with status: \(process.terminationStatus) (no stderr output captured)"
                }
                
                if errorString.isEmpty {
                    switch process.terminationStatus {
                    case 126:
                        throw VMAFError.permissionDenied
                    case 127:
                        throw VMAFError.executableNotFound
                    case 234:
                        throw VMAFError.sandboxViolation
                    default:
                        errorMessage = "FFmpeg exited with status: \(process.terminationStatus)"
                    }
                }
                
                throw VMAFError.ffmpegError(errorMessage)
            }
            
            // Read and parse the JSON log file
            let jsonData = try Data(contentsOf: logFile)
            print("JSON log file contents: \(String(data: jsonData, encoding: .utf8) ?? "Invalid JSON")")
            
            let decoder = JSONDecoder()
            let vmafData = try decoder.decode(VMAFData.self, from: jsonData)
            
            // Clean up the temporary file
            try? FileManager.default.removeItem(at: logFile)
            
            // Extract VMAF metrics
            guard let vmafMetrics = vmafData.pooledMetrics["vmaf"] else {
                print("No VMAF metrics found in JSON data")
                throw VMAFError.missingMetrics
            }
            
            // Calculate duration and frame count
            let frameCount = vmafData.frames.count
            let duration = TimeInterval(frameCount) / 30.0 // Assuming 30fps, we'll need to get actual fps
            
            return VMAFResult(
                score: vmafMetrics.mean,
                minScore: vmafMetrics.min,
                maxScore: vmafMetrics.max,
                harmonicMean: vmafMetrics.harmonicMean,
                frameMetrics: vmafData.frames,
                duration: duration,
                frameCount: frameCount,
                libvmafVersion: vmafData.libvmafVersion
            )
        } catch {
            print("Error during VMAF calculation: \(error)")
            if lastErrorOutput.isEmpty {
                var details = "Error: \(error)\n"
                if let status = lastTerminationStatus {
                    details += "FFmpeg exit status: \(status)\n"
                }
                lastErrorOutput = details
            }
            throw error
        }
    }
    
    // Parse ffmpeg output to extract frame progress information
    private func parseFFmpegOutput(_ output: String) {
        // Example of ffmpeg output: 
        // "frame=  301 fps= 65 q=-0.0 size=N/A time=00:00:10.03 bitrate=N/A speed=2.17x"
        let lines = output.split(separator: "\n")
        for line in lines {
            if line.contains("frame=") && line.contains("fps=") {
                let components = line.split(separator: " ").filter { !$0.isEmpty }
                
                var frameCount = 0
                var fps = 0.0
                var timeString = ""
                
                for i in 0..<components.count - 1 {
                    if components[i] == "frame=" {
                        if let count = Int(components[i+1].trimmingCharacters(in: .whitespaces)) {
                            frameCount = count
                        }
                    } else if components[i] == "fps=" {
                        if let fpsValue = Double(components[i+1].trimmingCharacters(in: .whitespaces)) {
                            fps = fpsValue
                        }
                    } else if components[i] == "time=" {
                        timeString = String(components[i+1])
                    }
                }
                
                // Calculate progress percentage if we have time information
                var progress = 0.0
                if !timeString.isEmpty {
                    // Parse time string like "00:00:10.03"
                    let timeParts = timeString.split(separator: ":")
                    if timeParts.count == 3, 
                       let hours = Double(timeParts[0]),
                       let minutes = Double(timeParts[1]),
                       let seconds = Double(timeParts[2]) {
                        
                        let totalSeconds = hours * 3600 + minutes * 60 + seconds
                        // Estimate progress (assuming we know total duration, otherwise use indeterminate progress)
                        progress = totalSeconds / 100.0 // Just a placeholder, would be better with actual video duration
                    }
                }
                
                // Notify delegate of progress update
                DispatchQueue.main.async { [weak self] in
                    let total = self?.estimatedTotalFrames ?? 0
                    self?.delegate?.vmafCalculatorDidUpdateProgress(
                        frameCount: frameCount,
                        fps: fps,
                        progress: progress,
                        totalFrames: total
                    )
                }
            }
        }
    }
    
    // Return the last ffmpeg command that was run
    func getLastCommand() -> String {
        return lastCommand
    }
    
    // Return the last captured ffmpeg (stderr) output or error details.
    func getLastErrorOutput() -> String {
        return lastErrorOutput
    }
    
    // Return the last termination status if available.
    func getLastTerminationStatus() -> Int32? {
        return lastTerminationStatus
    }
}

// MARK: - Supporting Types
extension VMAFCalculator {
    enum VMAFError: Error {
        case missingMetrics
        case ffmpegError(String)
        case permissionDenied
        case executableNotFound
        case sandboxViolation
        case modelNotFound(String)
        case resolutionMismatch(
            referenceWidth: Int,
            referenceHeight: Int,
            comparisonWidth: Int,
            comparisonHeight: Int
        )
        case missingVideoTrack
        case engineUnavailable(EngineHelper.Problem)
        
        var localizedDescription: String {
            switch self {
            case .missingMetrics:
                return "VMAF metrics could not be found in the output"
            case .ffmpegError(let message):
                return "FFmpeg error: \(message)"
            case .permissionDenied:
                return "Permission denied: Cannot execute ffmpeg. Make sure ffmpeg is properly signed during build."
            case .executableNotFound:
                return "FFmpeg executable not found. Make sure it's included in the app bundle."
            case .sandboxViolation:
                return "Sandbox violation: The app doesn't have permission to run ffmpeg. Check entitlements and code signing."
            case .modelNotFound(let name):
                return "VMAF model '\(name)' not found in app resources."
            case .resolutionMismatch:
                return "The resolutions of the Reference and Comparison videos do not match."
            case .missingVideoTrack:
                return "No video track found in one of the selected files."
            case .engineUnavailable(let problem):
                return problem.localizedDescription
            }
        }
    }
} 
