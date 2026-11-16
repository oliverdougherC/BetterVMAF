import Foundation
import PDFKit
import SwiftUI
import AppKit

class PDFGenerator {
    struct VideoInfo {
        let referenceVideo: URL
        let comparisonVideo: URL
    }
    
    static func generateReport(result: VMAFCalculator.VMAFResult, videoInfo: VideoInfo, includeVisualization: Bool, includeFrameData: Bool) -> Data {
        // Create PDF document
        let pdfDocument = PDFDocument()
        let pageSize = NSSize(width: 612, height: 792)  // 8.5x11 inches at 72 DPI
        
        // Create first page with content
        let firstPage = PDFPage()
        let firstPageBounds = CGRect(origin: .zero, size: pageSize)
        firstPage.setBounds(firstPageBounds, for: .mediaBox)
        
        // Create bitmap context for drawing
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pageSize.width),
            pixelsHigh: Int(pageSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        
        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        var yPosition: CGFloat = pageSize.height - 36
        
        // Draw title
        let titleFont = NSFont.boldSystemFont(ofSize: 18)
        let headerFont = NSFont.boldSystemFont(ofSize: 14)
        let bodyFont = NSFont.systemFont(ofSize: 12)
        
        drawText("VMAF Analysis Report", at: NSPoint(x: 36, y: yPosition), font: titleFont)
        yPosition -= 36
        
        // Draw video information
        drawText("Reference Video:", at: NSPoint(x: 36, y: yPosition), font: headerFont)
        yPosition -= 24
        drawText(videoInfo.referenceVideo.lastPathComponent, at: NSPoint(x: 48, y: yPosition), font: bodyFont)
        yPosition -= 24
        
        drawText("Comparison Video:", at: NSPoint(x: 36, y: yPosition), font: headerFont)
        yPosition -= 24
        drawText(videoInfo.comparisonVideo.lastPathComponent, at: NSPoint(x: 48, y: yPosition), font: bodyFont)
        yPosition -= 36
        
        // Draw summary results
        drawText("Summary Results", at: NSPoint(x: 36, y: yPosition), font: headerFont)
        yPosition -= 24
        
        let summaryData = [
            ("Overall VMAF Score:", String(format: "%.2f", result.score)),
            ("Score Range:", String(format: "%.2f - %.2f", result.minScore, result.maxScore)),
            ("Harmonic Mean:", String(format: "%.2f", result.harmonicMean)),
            ("Engine:", "libvmaf \(result.libvmafVersion ?? "unknown")")
        ]
        
        for (label, value) in summaryData {
            drawText(label, at: NSPoint(x: 48, y: yPosition), font: bodyFont)
            drawText(value, at: NSPoint(x: 200, y: yPosition), font: bodyFont)
            yPosition -= 24
        }
        yPosition -= 12
        
        // Draw the quality heat map
        if includeVisualization {
            drawText("Quality Heat Map", at: NSPoint(x: 36, y: yPosition), font: headerFont)
            yPosition -= 36

            if let heatMapImage = renderViewToImage(
                HeatMapView(timeline: QualityTimeline(metrics: result.frameMetrics), interactive: false)
                    .frame(width: pageSize.width - 72, height: 200)) {
                heatMapImage.draw(in: NSRect(x: 36, y: yPosition - 200,
                                           width: pageSize.width - 72, height: 200))
                yPosition -= 224
            }
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Create PDF data from the bitmap
        let image = NSImage(size: pageSize)
        image.addRepresentation(bitmapRep)
        let pdfPage = PDFPage(image: image)!
        pdfPage.setBounds(firstPageBounds, for: .mediaBox)
        pdfDocument.insert(pdfPage, at: 0)
        
        // Frame data on new pages if needed
        if includeFrameData {
            let motionFeature = result.frameMetrics.lazy.compactMap(\.motionReading?.feature).first ?? "integer_motion"
            let headers = ["Frame", "Time", "VMAF", "Motion (\(motionFeature))", "ADM2"]
            // Width per header text so "Motion (integer_motion2)" cannot spill
            // into ADM2; fixed [60,80,...] columns overlapped at 12pt bold.
            let columnWidths: [CGFloat] = Self.tableColumnWidths(headers: headers, font: bodyFont.bold())
            let startX: CGFloat = 48
            
            func createNewPage() -> (NSBitmapImageRep, NSGraphicsContext) {
                let imageRep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(pageSize.width),
                    pixelsHigh: Int(pageSize.height),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .calibratedRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                )!
                
                let context = NSGraphicsContext(bitmapImageRep: imageRep)!
                return (imageRep, context)
            }
            
            var (currentImageRep, currentContext) = createNewPage()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = currentContext
            
            yPosition = pageSize.height - 36
            
            func drawTableHeaders() {
                drawText("Frame Data", at: NSPoint(x: 36, y: yPosition), font: headerFont)
                yPosition -= 36
                var x = startX
                for (header, width) in zip(headers, columnWidths) {
                    drawText(header, at: NSPoint(x: x, y: yPosition), font: bodyFont.bold())
                    x += width
                }
                yPosition -= 24
            }
            
            drawTableHeaders()
            
            for metric in result.frameMetrics {
                if yPosition < 72 {
                    // Finish current page
                    NSGraphicsContext.restoreGraphicsState()
                    let image = NSImage(size: pageSize)
                    image.addRepresentation(currentImageRep)
                    let pdfPage = PDFPage(image: image)!
                    pdfPage.setBounds(firstPageBounds, for: .mediaBox)
                    pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
                    
                    // Start new page
                    (currentImageRep, currentContext) = createNewPage()
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = currentContext
                    
                    yPosition = pageSize.height - 36
                    drawTableHeaders()
                }
                
                var x = startX
                let rowData = [
                    String(metric.frameNumber),
                    String(format: "%.2fs", metric.timestamp),
                    String(format: "%.2f", metric.vmafScore),
                    metric.motionReading.map { String(format: "%.2f", $0.value) } ?? "--",
                    String(format: "%.2f", metric.integerAdm2)
                ]
                
                for (value, width) in zip(rowData, columnWidths) {
                    drawText(value, at: NSPoint(x: x, y: yPosition), font: bodyFont)
                    x += width
                }
                yPosition -= 20
            }
            
            // Add final data page
            NSGraphicsContext.restoreGraphicsState()
            let finalImage = NSImage(size: pageSize)
            finalImage.addRepresentation(currentImageRep)
            let finalPage = PDFPage(image: finalImage)!
            finalPage.setBounds(firstPageBounds, for: .mediaBox)
            pdfDocument.insert(finalPage, at: pdfDocument.pageCount)
        }
        
        return pdfDocument.dataRepresentation() ?? Data()
    }
    
    /// Table column widths sized to the header text (with padding), floored at
    /// 60pt, so no header can overlap its neighbor regardless of feature name.
    static func tableColumnWidths(headers: [String], font: NSFont) -> [CGFloat] {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return headers.map { header in
            let width = (header as NSString).size(withAttributes: attributes).width
            return max(60, ceil(width) + 16)
        }
    }

    private static func drawText(_ text: String, at point: NSPoint, font: NSFont) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        (text as NSString).draw(at: point, withAttributes: attributes)
    }
    
    private static func renderViewToImage(_ view: some View) -> NSImage? {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: 540, height: 200)  // 612 - 72 for margins
        
        hostingView.layout()
        let imageRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        hostingView.cacheDisplay(in: hostingView.bounds, to: imageRep!)
        
        let image = NSImage(size: hostingView.bounds.size)
        image.addRepresentation(imageRep!)
        return image
    }
}

private extension NSFont {
    func bold() -> NSFont {
        return NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
} 