import Foundation
import CryptoKit

/// Legal JSON representation of exceptional metric values; never zero-fills a missing output.
enum MetricValue: Codable, Equatable, Sendable {
    case finite(Double), positiveInfinity, negativeInfinity, undefined, unavailable
    var finiteValue: Double? { if case .finite(let value) = self { return value }; return nil }
    var doubleValue: Double? {
        switch self { case .finite(let value): return value; case .positiveInfinity: return .infinity
        case .negativeInfinity: return -.infinity; default: return nil }
    }
    init(_ value: Double) {
        if value.isNaN { self = .undefined }
        else if value == .infinity { self = .positiveInfinity }
        else if value == -.infinity { self = .negativeInfinity }
        else { self = .finite(value) }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .undefined; return }
        if let number = try? container.decode(Double.self) { self.init(number); return }
        let text = try container.decode(String.self)
        switch text.lowercased() {
        case "inf", "+inf", "infinity", "+infinity": self = .positiveInfinity
        case "-inf", "-infinity": self = .negativeInfinity
        case "nan", "undefined": self = .undefined
        case "unavailable": self = .unavailable
        default:
            guard let number = Double(text) else { throw AnalysisError.invalid("Invalid metric value: \(text)") }
            self.init(number)
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .finite(let value):
            guard value.isFinite else { throw AnalysisError.invalid("Nonfinite value incorrectly tagged finite.") }
            try container.encode(value)
        case .positiveInfinity: try container.encode("+infinity")
        case .negativeInfinity: try container.encode("-infinity")
        case .undefined: try container.encodeNil()
        case .unavailable: try container.encode("unavailable")
        }
    }
}

struct MetricDefinition: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let version: String
    let modelSHA256: String?
    let direction: String
    let unit: String
    let nominalRange: [Double]?
    let pooling: String
}

struct AnalysisFileIdentity: Codable, Sendable, Equatable {
    let url: URL
    let sha256: String
    let byteCount: Int64
    let modifiedAt: Date
    var filename: String { url.lastPathComponent }

    static func capture(_ url: URL) throws -> Self {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, let date = attributes[.modificationDate] as? Date else {
            throw AnalysisError.invalid("Cannot read file identity for \(url.lastPathComponent).")
        }
        return Self(url: url.standardizedFileURL, sha256: try hash(url), byteCount: size.int64Value, modifiedAt: date)
    }
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct AnalysisStream: Codable, Sendable, Equatable {
    let index: Int
    let codec: String
    let width: Int
    let height: Int
    let pixelFormat: String
    let bitDepth: Int
    let timeBase: String
    let averageFrameRate: String
    let sampleAspectRatio: String
    let rotation: Double
    let fieldOrder: String
    let colorMatrix: String
    let colorPrimaries: String
    let colorTransfer: String
    let colorRange: String
    let chromaLocation: String
    let duration: Double?
}

struct AnalysisFramePair: Codable, Sendable, Equatable {
    let index: Int
    let referencePTS: Int64
    let comparisonPTS: Int64
    let referenceTimeBase: String
    let comparisonTimeBase: String
    let referenceTimestamp: Double
    let comparisonTimestamp: Double
    let timestamp: Double
    let duration: Double
}

struct AnalysisConfiguration: Codable, Sendable, Equatable {
    enum ViewingProfile: String, Codable, Sendable, CaseIterable {
        case standard1080p, phone, television4K, television4K3H
        var label: String {
            switch self { case .standard1080p: return "1080p · 3H"; case .phone: return "Phone · 5H"
            case .television4K: return "4K · 1.5H"; case .television4K3H: return "4K · 3H" }
        }
        func modelName(hfr: Bool) -> String {
            let part: String
            switch self { case .standard1080p: part = "3d0h"; case .phone: part = "5d0h"
            case .television4K: part = "1d5h_2160"; case .television4K3H: part = "3d0h_2160" }
            return "vmaf_v1.0.16\(hfr ? "_hfr" : "")_\(part)"
        }
    }
    var viewingProfile: ViewingProfile = .standard1080p
    var threadCount: Int = min(8, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
    private(set) var mode: String = "standard"
    private(set) var coverage: String = "full"
    private(set) var correspondencePolicy: String = "strict-pts-and-content-v1"
    private(set) var eofPolicy: String = "shortest=1:repeatlast=0:eof_action=endall; exact frame count required"
    private(set) var colorPolicy: String = "BT.709 SDR; explicit full/limited to limited; 10-bit 4:2:0; no tone mapping"
    private(set) var geometryPolicy: String = "original equal coded canvas; square pixels; zero rotation; progressive; no scale/crop"
}

struct AnalysisMetricSample: Codable, Sendable {
    let pair: AnalysisFramePair
    let values: [String: MetricValue]
}

struct AnalysisResult: Codable, Sendable {
    let schemaVersion: Int
    let runID: UUID
    let createdAt: Date
    let reference: AnalysisFileIdentity
    let comparison: AnalysisFileIdentity
    let referenceStream: AnalysisStream
    let comparisonStream: AnalysisStream
    let configuration: AnalysisConfiguration
    let engineVersion: String
    let engineSHA256: String
    let probeSHA256: String
    let appVersion: String
    let modelIdentifier: String
    let modelSHA256: String
    let preprocessing: [String]
    let correspondenceNotes: [String]
    let definitions: [MetricDefinition]
    let samples: [AnalysisMetricSample]
    let pooledMetrics: [String: [String: MetricValue]]
    let aggregateMetrics: [String: MetricValue]
    let comparedDuration: Double
    let processingFPS: Double?
    var framePairs: [AnalysisFramePair] { samples.map(\.pair) }
    var sourceURL: URL { reference.url }
    var comparisonURL: URL { comparison.url }
}

enum AnalysisError: LocalizedError {
    case invalid(String), engine(String), process(Int32, String), missingMetric(String), busy
    var errorDescription: String? {
        switch self {
        case .invalid(let message), .engine(let message): return message
        case .process(let status, let stderr): return "Analysis engine exited with status \(status). \(stderr)"
        case .missingMetric(let name): return "The engine did not return a valid required \(name) measurement."
        case .busy: return "This calculator already owns an analysis. Cancel it and wait for completion before restarting."
        }
    }
}
