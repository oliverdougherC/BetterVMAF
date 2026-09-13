import Foundation
import CoreGraphics
import CoreText

/// Vector PDF drawing stays off the main actor and never instantiates a SwiftUI view.
enum PDFGenerator {
    static let maximumDetailedFrames = 500
    static func generateReport(result: VMAFCalculator.VMAFResult, options: ExportManager.ExportOptions) throws -> Data {
        guard let analysis = result.analysis else { throw AnalysisError.invalid("The result has no reproducible analysis provenance.") }
        if options.includeFrameData && analysis.samples.count > maximumDetailedFrames {
            throw AnalysisError.invalid("Detailed PDF is limited to \(maximumDetailedFrames) frames. Turn off every-frame data or choose CSV/JSON.")
        }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw AnalysisError.invalid("Cannot create PDF output.") }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw AnalysisError.invalid("Cannot create PDF drawing context.") }
        func text(_ value: String, _ top: CGFloat, _ size: CGFloat = 10, _ height: CGFloat = 28, x: CGFloat = 44, width: CGFloat = 524) {
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)]
            let string = NSAttributedString(string: value, attributes: attributes)
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(string), CFRange(location: 0, length: 0),
                CGPath(rect: CGRect(x: x, y: 792 - top - height, width: width, height: height), transform: nil), nil)
            CTFrameDraw(frame, context)
        }
        func begin(_ page: Int) {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            text("BetterVMAF · comparison record", 28, 9)
            text("\(page)", 752, 9, x: 544, width: 24)
        }
        try Task.checkCancellation()
        begin(1)
        text("Source versus encode", 56, 23, 36)
        text("Source: \(analysis.reference.filename)", 106, 11, 34)
        text("Encode: \(analysis.comparison.filename)", 143, 11, 34)
        text("\(analysis.samples.count) matched frames · \(String(format: "%.6f", analysis.comparedDuration)) seconds · \(analysis.configuration.coverage) coverage", 184)
        let saved = analysis.reference.byteCount - analysis.comparison.byteCount
        text("File size: \(analysis.reference.byteCount) → \(analysis.comparison.byteCount) bytes (\(saved) bytes saved)", 209)
        text("Size savings are separate from quality measurements.", 232, 9)
        var y: CGFloat = 266
        if options.includeAggregateMetrics {
            text("Named measurements · upstream aggregates", y, 13); y += 26
            let entries = [("VMAF v1 · upstream mean", ComparisonTradeoffs.nativeValue("vmaf", in: analysis), "model score"),
                           ("XPSNR · minimum native plane average", analysis.aggregateMetrics["xpsnr_min_plane"], "dB"),
                           ("Source CAMBI", ComparisonTradeoffs.nativeValue("cambi_source", in: analysis), "banding index"),
                           ("Encode CAMBI", ComparisonTradeoffs.nativeValue("cambi_encode", in: analysis), "banding index"),
                           ("Introduced CAMBI", ComparisonTradeoffs.nativeValue("cambi_full_reference", in: analysis), "banding index")]
            for (name, value, unit) in entries {
                let formatted = value.map { $0.finiteValue.map { String(format: "%.4f", $0) } ?? ExportManager.value($0) } ?? "unavailable"
                text("\(name): \(formatted) \(unit)", y); y += 19
            }
        }
        if options.includeGraphs {
            text("VMAF · \(String(format: "%.2f", result.minScore))–\(String(format: "%.2f", result.maxScore)) · 0–\(String(format: "%.3f", result.duration)) s", y, 12); y += 24
            try graph(result.frameMetrics, duration: result.duration, in: CGRect(x: 44, y: 792 - y - 104, width: 524, height: 104), context: context)
            y += 115
        }
        text("Viewing assumptions and provenance", y, 12); y += 24
        text("Model: \(analysis.modelIdentifier) · \(analysis.configuration.viewingProfile.label)", y, 9); y += 23
        text("\(analysis.configuration.colorPolicy)", y, 9, 34); y += 35
        text("Run: \(analysis.runID.uuidString)\nSource SHA-256: \(analysis.reference.sha256)\nEncode SHA-256: \(analysis.comparison.sha256)\nModel SHA-256: \(analysis.modelSHA256)\nEngine SHA-256: \(analysis.engineSHA256)\nApp \(analysis.appVersion) · streams source #\(analysis.referenceStream.index) / encode #\(analysis.comparisonStream.index)", y, 8, 70); y += 75
        text("Full hashes, streams, metric definitions, transforms and frame timestamps are available in JSON. Measurements identify differences; they do not establish a percentage of retained quality or visual transparency.", min(y, 690), 9, 48)
        context.endPDFPage()
        if options.includeFrameData {
            for start in stride(from: 0, to: analysis.samples.count, by: 32) {
                try Task.checkCancellation()
                begin(2 + start / 32)
                text("Analyzed frame data", 60, 20, 34)
                text("Frame        Time (seconds)                  VMAF", 106, 11)
                for (offset, sample) in analysis.samples[start..<min(start + 32, analysis.samples.count)].enumerated() {
                    let vmaf = sample.values["vmaf"].map(ExportManager.value) ?? "unavailable"
                    text("\(sample.pair.index)             \(String(format: "%.6f", sample.pair.timestamp))                         \(vmaf)", 138 + CGFloat(offset) * 18, 10)
                }
                text("All metric channels and original PTS are retained in CSV/JSON.", 729, 9)
                context.endPDFPage()
            }
        }
        context.closePDF()
        try Task.checkCancellation()
        return data as Data
    }
    private static func graph(_ frames: [VMAFCalculator.FrameMetric], duration: Double, in rect: CGRect, context: CGContext) throws {
        guard !frames.isEmpty else { return }
        let count = 512
        var low = [Double](repeating: .infinity, count: count)
        var high = [Double](repeating: -.infinity, count: count)
        var minimum = Double.infinity, maximum = -Double.infinity
        for (index, frame) in frames.enumerated() {
            if index % 1024 == 0 { try Task.checkCancellation() }
            guard frame.vmafScore.isFinite else { continue }
            let bucket = min(count - 1, max(0, Int(frame.timestamp / max(duration, 0.001) * Double(count - 1))))
            low[bucket] = min(low[bucket], frame.vmafScore); high[bucket] = max(high[bucket], frame.vmafScore)
            minimum = min(minimum, frame.vmafScore); maximum = max(maximum, frame.vmafScore)
        }
        guard minimum.isFinite else { return }
        let padding = max((maximum - minimum) * 0.1, 0.5)
        let domainMinimum = minimum - padding
        let span = maximum - minimum + padding * 2
        context.setStrokeColor(CGColor(gray: 0.75, alpha: 1)); context.setLineWidth(0.5); context.stroke(rect)
        context.setStrokeColor(CGColor(red: 0.12, green: 0.32, blue: 0.70, alpha: 1)); context.setLineWidth(1)
        for index in 0..<count where low[index].isFinite {
            let x = rect.minX + CGFloat(index) / CGFloat(count - 1) * rect.width
            let y1 = rect.minY + 4 + (low[index] - domainMinimum) / span * (rect.height - 8)
            let y2 = rect.minY + 4 + (high[index] - domainMinimum) / span * (rect.height - 8)
            context.move(to: CGPoint(x: x, y: y1)); context.addLine(to: CGPoint(x: x, y: max(y1 + 0.7, y2)))
        }
        context.strokePath()
        var started = false
        for index in 0..<count where low[index].isFinite {
            let x = rect.minX + CGFloat(index) / CGFloat(count - 1) * rect.width
            let y = rect.minY + 4 + ((low[index] + high[index]) / 2 - domainMinimum) / span * (rect.height - 8)
            if started { context.addLine(to: CGPoint(x: x, y: y)) }
            else { context.move(to: CGPoint(x: x, y: y)); started = true }
        }
        context.strokePath()
    }
}
