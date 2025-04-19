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
    }
    
    // Add delegate for progress updates
    protocol VMAFCalculatorDelegate {
        func vmafCalculatorDidUpdateProgress(frameCount: Int, fps: Double, progress: Double)
    }
    
    var delegate: VMAFCalculatorDelegate?
    private var lastCommand: String = ""
    
    struct FrameMetric: Codable, Identifiable {
        let frameNumber: Int
        let vmafScore: Double
        let integerMotion: Double
        let integerMotion2: Double
        let integerAdm2: Double
        let integerAdmScales: [Double]
        let integerVifScales: [Double]
        
        // Identifiable conformance
        var id: Int { frameNumber }
        
        // Computed property for timestamp (assuming 30fps)
        var timestamp: TimeInterval {
            TimeInterval(frameNumber - 1) / 30.0
        }
        
        init(frameNumber: Int,
             vmafScore: Double,
             integerMotion: Double,
             integerMotion2: Double,
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
            integerMotion = try metricsContainer.decode(Double.self, forKey: .integerMotion)
            integerMotion2 = try metricsContainer.decode(Double.self, forKey: .integerMotion2)
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
            try metricsContainer.encode(integerMotion, forKey: .integerMotion)
            try metricsContainer.encode(integerMotion2, forKey: .integerMotion2)
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
        
        enum CodingKeys: String, CodingKey {
            case frames
            case pooledMetrics = "pooled_metrics"
            case aggregateMetrics = "aggregate_metrics"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            frames = try container.decode([FrameMetric].self, forKey: .frames)
            pooledMetrics = try container.decode([String: VMAFMetrics].self, forKey: .pooledMetrics)
            aggregateMetrics = try container.decode([String: String].self, forKey: .aggregateMetrics)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(frames, forKey: .frames)
            try container.encode(pooledMetrics, forKey: .pooledMetrics)
            try container.encode(aggregateMetrics, forKey: .aggregateMetrics)
        }
    }
    
    private let ffmpegPath: String
    
    init() {
        // Get the path to ffmpeg in the app bundle
        if let bundlePath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            ffmpegPath = bundlePath
            print("Using bundled ffmpeg at path: \(bundlePath)")
            
            // Make the binary executable - note that in a sandboxed app, we can't modify permissions
            // We need to rely on the app being properly code signed with the ffmpeg executable
            // already having the proper permissions set during the build process
            
            // Check if the file is executable
            var isExecutable = false
            let fileManager = FileManager.default
            if let attributes = try? fileManager.attributesOfItem(atPath: bundlePath),
               let posixPermissions = attributes[.posixPermissions] as? NSNumber {
                let permissions = posixPermissions.intValue
                isExecutable = (permissions & 0o111) != 0 // Check if any execute bit is set
            }
            
            if !isExecutable {
                print("Warning: ffmpeg does not have executable permissions. Using alternative approach.")
                // Instead of trying to chmod, we'll try to use the executable through a different mechanism
                // or fallback to system ffmpeg
            }
        } else {
            // Fallback to system ffmpeg if not found in bundle
            ffmpegPath = "/opt/homebrew/bin/ffmpeg"
            print("Warning: Using system ffmpeg at path: \(ffmpegPath)")
        }
    }
    
    func calculateVMAF(referenceVideo: URL, comparisonVideo: URL) async throws -> VMAFResult {
        // Create a temporary file for the VMAF JSON log
        let tempDir = FileManager.default.temporaryDirectory
        let logFile = tempDir.appendingPathComponent(UUID().uuidString + ".json")
        
        // Ensure the temporary directory exists and is writable
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let lavfiFilterGraph = "[1:v]setpts=PTS-STARTPTS[dist];[0:v]setpts=PTS-STARTPTS[ref];[dist][ref]libvmaf=log_fmt=json:log_path=\(logFile.path):n_threads=99"
        
        
        // Build the ffmpeg command with enhanced metrics collection
        let command = [
            ffmpegPath,                  // Your variable for the FFmpeg executable path
            "-hide_banner",              // Optional: Hides version/build info
            "-i", referenceVideo.path,   // Input 0 [0:v] - The Reference Video
            "-i", comparisonVideo.path,  // Input 1 [1:v] - The Video to Compare (Distorted)
            "-lavfi", lavfiFilterGraph,  // Use the explicitly mapped complex filtergraph
            "-f", "null",                // Don't create an output video file
            "-"                          // Pipe output (though -f null makes this less relevant here)
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
        
        let pipe = Pipe()
        process.standardError = pipe
        
        // Set up a file handle to monitor stderr for progress updates
        let fileHandle = pipe.fileHandleForReading
        
        // Setup a notification to read stderr data as it becomes available
        NotificationCenter.default.addObserver(forName: .NSFileHandleDataAvailable, object: fileHandle, queue: .main) { [weak self] _ in
            let data = fileHandle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    // Parse progress information from ffmpeg output
                    self?.parseFFmpegOutput(output)
                }
                fileHandle.waitForDataInBackgroundAndNotify()
            }
        }
        fileHandle.waitForDataInBackgroundAndNotify()
        
        do {
            try process.run()
            
            // Wait for process to complete
            process.waitUntilExit()
            
            // Clean up notification observer
            NotificationCenter.default.removeObserver(self, name: .NSFileHandleDataAvailable, object: fileHandle)
            
            // Read all error output
            let errorData = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("FFmpeg output: \(errorString)")
            
            // Check if process failed
            if process.terminationStatus != 0 {
                print("FFmpeg failed with status: \(process.terminationStatus)")
                
                // Provide more detailed error information
                var errorMessage = errorString
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
                frameCount: frameCount
            )
        } catch {
            print("Error during VMAF calculation: \(error)")
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
                    self?.delegate?.vmafCalculatorDidUpdateProgress(frameCount: frameCount, fps: fps, progress: progress)
                }
            }
        }
    }
    
    // Return the last ffmpeg command that was run
    func getLastCommand() -> String {
        return lastCommand
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
            }
        }
    }
} 
