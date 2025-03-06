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
        var csv = "Frame Number,Timestamp,VMAF Score,Motion,ADM2\n"
        
        // Add frame-by-frame data if requested
        if options.includeFrameData {
            for metric in result.frameMetrics {
                let row = "\(metric.frameNumber),\(metric.timestamp),\(metric.vmafScore),\(metric.integerMotion),\(metric.integerAdm2)\n"
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
        }
        
        return csv
    }
    
    func exportToJSON(result: VMAFCalculator.VMAFResult, options: ExportOptions) throws -> Data {
        var exportDict: [String: Any] = [:]
        
        if options.includeFrameData {
            exportDict["frames"] = result.frameMetrics.map { metric in
                [
                    "frameNumber": metric.frameNumber,
                    "timestamp": metric.timestamp,
                    "vmafScore": metric.vmafScore,
                    "motion": metric.integerMotion,
                    "adm2": metric.integerAdm2
                ]
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