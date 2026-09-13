import Foundation
import UniformTypeIdentifiers

struct ExportManager: Sendable {
    enum ExportFormat: String, Sendable, CaseIterable {
        case csv, json, pdf
        var fileExtension: String { rawValue }
        var contentType: UTType { switch self { case .csv: return .commaSeparatedText; case .json: return .json; case .pdf: return .pdf } }
    }
    struct ExportOptions: Sendable {
        var includeFrameData = false
        var includeAggregateMetrics = true
        var includeGraphs = true
    }

    /// Runs in the caller's detached task. Only atomically replace the destination after complete success.
    func write(result: VMAFCalculator.VMAFResult, format: ExportFormat, options: ExportOptions, to destination: URL) throws {
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        // A save-panel grant covers the selected file, not arbitrary siblings. Foundation creates
        // a sandbox-compatible replacement directory on the destination volume for atomic publication.
        let stagingDirectory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destination, create: true)
        let staging = stagingDirectory.appendingPathComponent("report.\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        if format == .csv {
            guard FileManager.default.createFile(atPath: staging.path, contents: nil) else { throw AnalysisError.invalid("Cannot create export at this destination.") }
            let handle = try FileHandle(forWritingTo: staging)
            defer { try? handle.close() }
            var buffer = ""
            try csvRows(result: result, options: options) { row in
                buffer += row
                if buffer.utf8.count >= 64 * 1024 { try handle.write(contentsOf: Data(buffer.utf8)); buffer = "" }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: Data(buffer.utf8)) }
            try handle.synchronize()
        } else {
            let data = try export(result: result, format: format, options: options)
            try Task.checkCancellation()
            try data.write(to: staging)
        }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else { try FileManager.default.moveItem(at: staging, to: destination) }
    }

    func exportToJSON(result: VMAFCalculator.VMAFResult, options: ExportOptions) throws -> Data {
        let analysis = try requireAnalysis(result)
        try Task.checkCancellation()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(AnalysisExport(analysis: analysis, options: options))
        try Task.checkCancellation()
        return data
    }
    func exportToCSV(result: VMAFCalculator.VMAFResult, options: ExportOptions) throws -> String {
        var csv = ""
        try csvRows(result: result, options: options) { csv += $0 }
        return csv
    }
    func exportToPDF(result: VMAFCalculator.VMAFResult, options: ExportOptions) throws -> Data {
        _ = try requireAnalysis(result)
        return try PDFGenerator.generateReport(result: result, options: options)
    }
    func export(result: VMAFCalculator.VMAFResult, format: ExportFormat, options: ExportOptions) throws -> Data {
        switch format {
        case .csv: return Data(try exportToCSV(result: result, options: options).utf8)
        case .json: return try exportToJSON(result: result, options: options)
        case .pdf: return try exportToPDF(result: result, options: options)
        }
    }
    private func requireAnalysis(_ result: VMAFCalculator.VMAFResult) throws -> AnalysisResult {
        guard let analysis = result.analysis else { throw AnalysisError.invalid("This legacy result has no immutable provenance. Analyze the videos again to export a reproducible report.") }
        return analysis
    }
    private func csvRows(result: VMAFCalculator.VMAFResult, options: ExportOptions, emit: (String) throws -> Void) throws {
        let analysis = try requireAnalysis(result)
        func row(_ fields: [String]) throws { try emit(fields.map(Self.csvCell).joined(separator: ",") + "\n") }
        try row(["record_type", "frame", "timestamp_seconds", "duration_seconds", "reference_timestamp_seconds", "comparison_timestamp_seconds", "reference_pts", "comparison_pts", "metric", "value", "context_json"])
        var metadataOptions = options
        metadataOptions.includeFrameData = false
        metadataOptions.includeAggregateMetrics = false
        let metadata = try exportToJSON(result: result, options: metadataOptions)
        try row(["provenance", "", "", "", "", "", "", "", "", "", String(decoding: metadata, as: UTF8.self)])
        if options.includeFrameData {
            for (index, sample) in analysis.samples.enumerated() {
                if index % 256 == 0 { try Task.checkCancellation() }
                let pair = sample.pair
                for key in sample.values.keys.sorted() {
                    try row(["frame", String(pair.index), String(pair.timestamp), String(pair.duration), String(pair.referenceTimestamp), String(pair.comparisonTimestamp), String(pair.referencePTS), String(pair.comparisonPTS), key, Self.value(sample.values[key]!), ""])
                }
            }
        }
        if options.includeAggregateMetrics {
            for key in analysis.aggregateMetrics.keys.sorted() {
                try row(["aggregate", "", "", "", "", "", "", "", key, Self.value(analysis.aggregateMetrics[key]!), ""])
            }
            for key in analysis.pooledMetrics.keys.sorted() {
                for pooling in analysis.pooledMetrics[key]!.keys.sorted() {
                    try row(["upstream_pool", "", "", "", "", "", "", "", key + "." + pooling, Self.value(analysis.pooledMetrics[key]![pooling]!), ""])
                }
            }
        }
        try Task.checkCancellation()
    }
    static func csvCell(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    static func value(_ value: MetricValue) -> String {
        switch value {
        case .finite(let number): return String(number)
        case .positiveInfinity: return "+infinity"
        case .negativeInfinity: return "-infinity"
        case .undefined: return "undefined"
        case .unavailable: return "unavailable"
        }
    }
}

/// Uses the analysis schema's exact field names. Unselected payloads are omitted, never zero-filled.
private struct AnalysisExport: Encodable {
    let analysis: AnalysisResult
    let options: ExportManager.ExportOptions
    enum Key: String, CodingKey {
        case schemaVersion, runID, createdAt, reference, comparison, referenceStream, comparisonStream,
             configuration, engineVersion, engineSHA256, probeSHA256, appVersion, modelIdentifier,
             modelSHA256, preprocessing, correspondenceNotes, definitions, samples, pooledMetrics,
             aggregateMetrics, comparedDuration, processingFPS
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        let a = analysis
        try c.encode(a.schemaVersion, forKey: .schemaVersion)
        try c.encode(a.runID, forKey: .runID)
        try c.encode(a.createdAt, forKey: .createdAt)
        try c.encode(a.reference, forKey: .reference)
        try c.encode(a.comparison, forKey: .comparison)
        try c.encode(a.referenceStream, forKey: .referenceStream)
        try c.encode(a.comparisonStream, forKey: .comparisonStream)
        try c.encode(a.configuration, forKey: .configuration)
        try c.encode(a.engineVersion, forKey: .engineVersion)
        try c.encode(a.engineSHA256, forKey: .engineSHA256)
        try c.encode(a.probeSHA256, forKey: .probeSHA256)
        try c.encode(a.appVersion, forKey: .appVersion)
        try c.encode(a.modelIdentifier, forKey: .modelIdentifier)
        try c.encode(a.modelSHA256, forKey: .modelSHA256)
        try c.encode(a.preprocessing, forKey: .preprocessing)
        try c.encode(a.correspondenceNotes, forKey: .correspondenceNotes)
        try c.encode(a.definitions, forKey: .definitions)
        try c.encode(a.comparedDuration, forKey: .comparedDuration)
        try c.encodeIfPresent(a.processingFPS, forKey: .processingFPS)
        if options.includeFrameData {
            var frames = c.nestedUnkeyedContainer(forKey: .samples)
            for (index, sample) in a.samples.enumerated() {
                if index % 256 == 0 { try Task.checkCancellation() }
                try frames.encode(sample)
            }
        }
        if options.includeAggregateMetrics {
            try c.encode(a.pooledMetrics, forKey: .pooledMetrics)
            try c.encode(a.aggregateMetrics, forKey: .aggregateMetrics)
        }
    }
}
