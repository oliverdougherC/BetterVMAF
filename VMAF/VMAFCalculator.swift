//
//  VMAFCalculator.swift
//  VMAF
//
//  Created by Oliver Dougherty on 3/4/25.
//


import Foundation
import AVFoundation

class VMAFCalculator {
    struct VMAFResult {
        let score: Double
        let minScore: Double
        let maxScore: Double
        let harmonicMean: Double
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
        
        // Build the ffmpeg command
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
            
            return VMAFResult(
                score: vmafMetrics.mean,
                minScore: vmafMetrics.min,
                maxScore: vmafMetrics.max,
                harmonicMean: vmafMetrics.harmonicMean
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
    
    struct VMAFData: Codable {
        let pooledMetrics: [String: VMAFMetrics]
        
        enum CodingKeys: String, CodingKey {
            case pooledMetrics = "pooled_metrics"
        }
    }
} 
