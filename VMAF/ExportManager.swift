import Foundation
import SwiftUI
import UniformTypeIdentifiers

class ExportManager {
    enum ExportFormat {
        case csv
        case json
        case pdf
        
        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .json: return "json"
            case .pdf: return "pdf"
            }
        }
        
        var contentType: UTType {
            switch self {
            case .csv: return .commaSeparatedText
            case .json: return .json
            case .pdf: return .pdf
            }
        }
    }
    
    struct ExportOptions {
        var includeFrameData: Bool = true
        var includeAggregateMetrics: Bool = true
        var includeGraphs: Bool = true
        var templateName: String = "default"
    }
    
    func exportToCSV(result: VMAFCalculator.VMAFResult, options: ExportOptions) throws -> String {
        // One uniform table: header and frame records all have five fields so
        // parsers infer a stable schema; provenance lives in its own trailing
        // sections instead of a short row above the header.
        // Name the Motion column after the libvmaf feature that produced it;
        // the legacy `integer_motion` and libvmaf 3.x `integer_motion2` are
        // different measurements and must not share an unlabeled column.
        let motionFeature = result.frameMetrics.lazy.compactMap(\.motionReading?.feature).first ?? ""
        var csv = "Frame Number,Timestamp,VMAF Score,Motion\(motionFeature.isEmpty ? "" : " (\(motionFeature))"),ADM2\n"

        // Add frame-by-frame data if requested
        if options.includeFrameData {
            for metric in result.frameMetrics {
                let motion = metric.motionReading.map { String($0.value) } ?? ""
                let row = "\(metric.frameNumber),\(metric.timestamp),\(metric.vmafScore),\(motion),\(metric.integerAdm2)\n"
                csv += row
            }
        }

        // Add aggregate metrics if requested
        if options.includeAggregateMetrics {
            csv += "\n\nAggregate Metrics\n"
            csv += "Overall VMAF Score,\(result.score)\n"
            csv += "Min Score,\(result.minScore)\n"
            csv += "Max Score,\(result.maxScore)\n"
            csv += "Harmonic Mean,\(result.harmonicMean)\n"
            csv += "\n\nEngine\n"
            csv += "Metric,libvmaf\n"
            csv += "Version,\(result.libvmafVersion ?? "unknown")\n"
            if !motionFeature.isEmpty {
                csv += "Motion feature,\(motionFeature)\n"
            }
        }

        return csv
    }
    
    func exportToJSON(result: VMAFCalculator.VMAFResult, options: ExportOptions) throws -> Data {
        var exportDict: [String: Any] = [:]
        exportDict["engine"] = [
            "metric": "libvmaf",
            "version": result.libvmafVersion ?? "unknown"
        ]
        
        if options.includeFrameData {
            exportDict["frames"] = result.frameMetrics.map { metric -> [String: Any] in
                var frame: [String: Any] = [
                    "frameNumber": metric.frameNumber,
                    "timestamp": metric.timestamp,
                    "vmafScore": metric.vmafScore,
                    "adm2": metric.integerAdm2
                ]
                // Key the motion value by its libvmaf feature identity, and omit
                // the feature entirely when the engine did not report it — an
                // absent measurement is unavailable, never a fabricated 0.0.
                if let reading = metric.motionReading {
                    frame[reading.feature] = reading.value
                }
                return frame
            }
        }
        
        if options.includeAggregateMetrics {
            exportDict["aggregateMetrics"] = [
                "overallScore": result.score,
                "minScore": result.minScore,
                "maxScore": result.maxScore,
                "harmonicMean": result.harmonicMean
            ]
        }
        
        return try JSONSerialization.data(withJSONObject: exportDict, options: .prettyPrinted)
    }
    
    func exportToPDF(result: VMAFCalculator.VMAFResult, options: ExportOptions) throws -> Data {
        guard let referenceVideo = UserDefaults.standard.url(forKey: "LastReferenceVideo"),
              let comparisonVideo = UserDefaults.standard.url(forKey: "LastComparisonVideo") else {
            throw NSError(domain: "ExportManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Video paths not available"])
        }
        
        let videoInfo = PDFGenerator.VideoInfo(
            referenceVideo: referenceVideo,
            comparisonVideo: comparisonVideo
        )
        
        return PDFGenerator.generateReport(
            result: result,
            videoInfo: videoInfo,
            includeGraphs: options.includeGraphs,
            includeFrameData: options.includeFrameData
        )
    }
    
    func export(result: VMAFCalculator.VMAFResult, format: ExportFormat, options: ExportOptions) throws -> Data {
        switch format {
        case .csv:
            let csvString = try exportToCSV(result: result, options: options)
            return csvString.data(using: .utf8) ?? Data()
            
        case .json:
            return try exportToJSON(result: result, options: options)
            
        case .pdf:
            return try exportToPDF(result: result, options: options)
        }
    }
} 