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
        } else {
            // Fallback to system ffmpeg if not found in bundle
            ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        }
    }
    
    func calculateVMAF(referenceVideo: URL, comparisonVideo: URL) async throws -> VMAFResult {
        // Create a temporary file for the VMAF JSON log
        let tempDir = FileManager.default.temporaryDirectory
        let logFile = tempDir.appendingPathComponent(UUID().uuidString + ".json")
        
        // Ensure the temporary directory exists and is writable
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Build the ffmpeg command with enhanced metrics collection
        let command = [
            ffmpegPath,
            "-hide_banner",
            "-i", referenceVideo.path,
            "-i", comparisonVideo.path,
            "-lavfi", "libvmaf=log_fmt=json:log_path=\(logFile.path):n_threads=4",
            "-f", "null",
            "-"
        ]
        
        print("Running FFmpeg command: \(command.joined(separator: " "))")
        
        // Run the command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        
        // Set up environment variables
        var env = ProcessInfo.processInfo.environment
        if let libPath = Bundle.main.path(forResource: "lib", ofType: nil) {
            env["DYLD_LIBRARY_PATH"] = libPath
        }
        process.environment = env
        
        let pipe = Pipe()
        process.standardError = pipe
        
        do {
            try process.run()
            
            // Read error output
            let errorData = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("FFmpeg output: \(errorString)")
            
            process.waitUntilExit()
            
            // Check if process failed
            if process.terminationStatus != 0 {
                print("FFmpeg failed with status: \(process.terminationStatus)")
                throw VMAFError.ffmpegError(errorString)
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
}

// MARK: - Supporting Types
extension VMAFCalculator {
    enum VMAFError: Error {
        case missingMetrics
        case ffmpegError(String)
    }
} 
