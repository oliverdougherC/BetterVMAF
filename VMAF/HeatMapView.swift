import SwiftUI
import Charts

struct HeatMapView: View {
    let frameMetrics: [VMAFCalculator.FrameMetric]
    @State private var selectedTimeRange: ClosedRange<TimeInterval>?
    @State private var isZoomed = false
    @State private var zoomLevel: Double = 1.0
    @State private var scrollPosition: TimeInterval = 0
    @State private var hoveredFrame: VMAFCalculator.FrameMetric?
    @State private var hoverDebounceTimer: Timer?
    @State private var isHoverBoxVisible = false
    @State private var lastHoveredLocation: CGPoint?
    @State private var chartProxy: ChartProxy?
    
    private var timeRange: ClosedRange<TimeInterval> {
        guard let firstFrame = frameMetrics.first,
              let lastFrame = frameMetrics.last else {
            return 0...1
        }
        return firstFrame.timestamp...lastFrame.timestamp
    }
    
    private var displayRange: ClosedRange<TimeInterval> {
        if !isZoomed {
            return timeRange
        }
        
        let totalDuration = timeRange.upperBound - timeRange.lowerBound
        let visibleDuration = totalDuration / zoomLevel
        let start = min(max(scrollPosition, timeRange.lowerBound), timeRange.upperBound - visibleDuration)
        let end = min(start + visibleDuration, timeRange.upperBound)
        return start...end
    }
    
    private var filteredMetrics: [VMAFCalculator.FrameMetric] {
        frameMetrics.filter { metric in
            displayRange.contains(metric.timestamp)
        }
    }
    
    private var yAxisRange: ClosedRange<Double> {
        let minScore = frameMetrics.min { $0.vmafScore < $1.vmafScore }?.vmafScore ?? 0.0
        let maxScore = frameMetrics.max { $0.vmafScore < $1.vmafScore }?.vmafScore ?? 100.0
        return minScore...maxScore
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Chart with heat map visualization
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // Heat map chart
                    Chart(filteredMetrics) { metric in
                        // Background grid lines
                        ForEach([10, 20, 30, 40, 50, 60, 70, 80, 90, 100], id: \.self) { value in
                            RuleMark(y: .value("Grid", value))
                                .foregroundStyle(.gray.opacity(0.1))
                        }
                        
                        // Heat map points
                        PointMark(
                            x: .value("Time", metric.timestamp),
                            y: .value("VMAF", metric.vmafScore)
                        )
                        .foregroundStyle(heatMapColor(for: metric.vmafScore))
                        .symbol(.circle)
                        .symbolSize(hoveredFrame?.frameNumber == metric.frameNumber ? 30 : 20)
                    }
                    .chartXScale(domain: displayRange)
                    .chartYScale(domain: yAxisRange)
                    .animation(.easeInOut(duration: 0.2), value: displayRange)
                    .animation(.easeInOut(duration: 0.2), value: zoomLevel)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 1)) { value in
                            if let time = value.as(TimeInterval.self) {
                                AxisValueLabel(formatTime(time))
                                    .font(.system(size: 9))
                            }
                            AxisGridLine()
                                .foregroundStyle(.clear)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .stride(by: 10)) { value in
                            if let score = value.as(Double.self) {
                                AxisValueLabel(String(format: "%.0f", score))
                                    .font(.system(size: 9))
                            }
                            AxisGridLine()
                                .foregroundStyle(.gray.opacity(0.1))
                        }
                    }
                    .chartLegend(.hidden)
                    .chartXAxisLabel("")
                    .chartYAxisLabel("")
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onAppear {
                                    chartProxy = proxy
                                }
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        lastHoveredLocation = location
                                        
                                        hoverDebounceTimer?.invalidate()
                                        hoverDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
                                            if let (frame, distance) = findNearestFrame(at: location, in: geometry, proxy: proxy),
                                               distance < 30 {
                                                withAnimation(.easeOut(duration: 0.15)) {
                                                    if hoveredFrame?.frameNumber != frame.frameNumber {
                                                        hoveredFrame = frame
                                                        isHoverBoxVisible = true
                                                    }
                                                }
                                            }
                                        }
                                    case .ended:
                                        hoverDebounceTimer?.invalidate()
                                        lastHoveredLocation = nil
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            isHoverBoxVisible = false
                                            hoveredFrame = nil
                                        }
                                    }
                                }
                        }
                    }
                    
                    // Hover details popup
                    if let frame = hoveredFrame, let proxy = chartProxy, isHoverBoxVisible {
                        GeometryReader { geometry in
                            frameDetailsView(frame: frame)
                                .padding(4)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(4)
                                .shadow(radius: 2)
                                .opacity(isHoverBoxVisible ? 1 : 0)
                                .offset(x: calculateHoverBoxOffset(for: frame, in: geometry),
                                      y: calculateVerticalPosition(for: frame, in: geometry, proxy: proxy))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
            .frame(minHeight: 120, maxHeight: .infinity)
            
            // Controls and info
            HStack {
                HStack(spacing: 4) {
                    Button(action: zoomOut) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.caption2)
                    }
                    .disabled(!isZoomed)
                    
                    Button(action: resetZoom) {
                        Text("Reset")
                            .font(.caption2)
                    }
                    .disabled(!isZoomed)
                    
                    Button(action: zoomIn) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.caption2)
                    }
                }
                
                Divider().frame(height: 12)
                
                Text("Frames: \(frameMetrics.count)")
                    .font(.system(size: 10))
                
                if isZoomed {
                    Text("(\(filteredMetrics.count) visible)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("• Zoom: \(String(format: "%.1fx", zoomLevel))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Color legend
                HStack(spacing: 8) {
                    Text("Quality:")
                        .font(.system(size: 10))
                    ForEach(["Poor", "Fair", "Good", "Excellent"], id: \.self) { label in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(heatMapColor(for: qualityValue(for: label)))
                                .frame(width: 8, height: 8)
                            Text(label)
                                .font(.system(size: 10))
                        }
                    }
                }
            }
            .frame(height: 24)
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
            
            // Navigation slider (only shows when zoomed)
            if isZoomed {
                VStack(spacing: 0) {
                    // Minimap
                    Chart(frameMetrics) { metric in
                        PointMark(
                            x: .value("Time", metric.timestamp),
                            y: .value("VMAF", metric.vmafScore)
                        )
                        .foregroundStyle(heatMapColor(for: metric.vmafScore))
                        .symbol(.circle)
                        .symbolSize(4)
                    }
                    .chartXScale(domain: timeRange)
                    .chartYScale(domain: yAxisRange)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartLegend(.hidden)
                    .frame(height: 20)
                    .overlay(
                        GeometryReader { geometry in
                            let totalDuration = timeRange.upperBound - timeRange.lowerBound
                            let visibleDuration = totalDuration / zoomLevel
                            let maxScroll = totalDuration - visibleDuration
                            let progress = (scrollPosition - timeRange.lowerBound) / maxScroll
                            let visibleWidth = geometry.size.width / zoomLevel
                            let maxOffset = geometry.size.width - visibleWidth
                            let xOffset = maxOffset * progress
                            
                            Rectangle()
                                .fill(.blue.opacity(0.2))
                                .frame(width: visibleWidth)
                                .offset(x: min(maxOffset, xOffset))
                        }
                    )
                    
                    // Slider
                    Slider(
                        value: Binding(
                            get: {
                                let totalDuration = timeRange.upperBound - timeRange.lowerBound
                                let visibleDuration = totalDuration / zoomLevel
                                let maxScroll = totalDuration - visibleDuration
                                return (scrollPosition - timeRange.lowerBound) / maxScroll
                            },
                            set: { newValue in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    let totalDuration = timeRange.upperBound - timeRange.lowerBound
                                    let visibleDuration = totalDuration / zoomLevel
                                    let maxScroll = totalDuration - visibleDuration
                                    scrollPosition = timeRange.lowerBound + (maxScroll * newValue)
                                    updateDisplayRange(scrollPosition: scrollPosition)
                                }
                            }
                        ),
                        in: 0...1
                    )
                    .padding(.horizontal, 8)
                }
                .frame(height: 40)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func heatMapColor(for score: Double) -> Color {
        let normalizedScore = (score - yAxisRange.lowerBound) / (yAxisRange.upperBound - yAxisRange.lowerBound)
        
        // Define color stops for the heat map
        let colors: [(Double, Color)] = [
            (0.0, .red),      // Poor
            (0.25, .orange), // Fair
            (0.5, .yellow),  // Good
            (0.75, .green),  // Very Good
            (1.0, .blue)     // Excellent
        ]
        
        // Find the appropriate color based on the normalized score
        for i in 0..<(colors.count - 1) {
            let (start, startColor) = colors[i]
            let (end, endColor) = colors[i + 1]
            
            if normalizedScore >= start && normalizedScore <= end {
                let t = (normalizedScore - start) / (end - start)
                return startColor.interpolate(to: endColor, amount: t)
            }
        }
        
        return colors.last?.1 ?? .blue
    }
    
    private func qualityValue(for label: String) -> Double {
        switch label {
        case "Poor": return yAxisRange.lowerBound
        case "Fair": return yAxisRange.lowerBound + (yAxisRange.upperBound - yAxisRange.lowerBound) * 0.25
        case "Good": return yAxisRange.lowerBound + (yAxisRange.upperBound - yAxisRange.lowerBound) * 0.5
        case "Excellent": return yAxisRange.upperBound
        default: return yAxisRange.lowerBound
        }
    }
    
    private func frameDetailsView(frame: VMAFCalculator.FrameMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Frame \(frame.frameNumber)")
                .font(.system(size: 10, weight: .bold))
            Text("VMAF: \(String(format: "%.2f", frame.vmafScore))")
            Text("Time: \(formatTime(frame.timestamp))")
            Text("Motion: \(String(format: "%.2f", frame.integerMotion))")
            Text("ADM2: \(String(format: "%.2f", frame.integerAdm2))")
        }
        .font(.system(size: 9))
        .fixedSize(horizontal: true, vertical: true)
    }
    
    private func findNearestFrame(at location: CGPoint, in geometry: GeometryProxy, proxy: ChartProxy) -> (VMAFCalculator.FrameMetric, CGFloat)? {
        let xPosition = location.x
        let yPosition = location.y
        
        let chartFrame = geometry.frame(in: .local)
        
        guard chartFrame.contains(CGPoint(x: xPosition, y: yPosition)) else { return nil }
        
        guard let _ = proxy.value(atX: xPosition) as TimeInterval?,
              let _ = proxy.value(atY: yPosition) as Double? else { return nil }
        
        return filteredMetrics
            .map { metric -> (VMAFCalculator.FrameMetric, CGFloat) in
                guard let metricX = proxy.position(forX: metric.timestamp) else {
                    return (metric, .infinity)
                }
                
                let xDistance = abs(metricX - xPosition)
                let distance = xDistance
                return (metric, distance)
            }
            .min { $0.1 < $1.1 }
    }
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomLevel = min(zoomLevel * 2, 10.0)
            isZoomed = zoomLevel > 1.0
            updateDisplayRange(zoomLevel: zoomLevel)
        }
    }
    
    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomLevel = max(zoomLevel / 2, 1.0)
            isZoomed = zoomLevel > 1.0
            updateDisplayRange(zoomLevel: zoomLevel)
        }
    }
    
    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomLevel = 1.0
            isZoomed = false
            scrollPosition = timeRange.lowerBound
            hoveredFrame = nil
        }
    }
    
    private func updateDisplayRange(zoomLevel: Double? = nil, scrollPosition: TimeInterval? = nil) {
        if let newScrollPosition = scrollPosition {
            self.scrollPosition = newScrollPosition
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func calculateHoverBoxOffset(for frame: VMAFCalculator.FrameMetric, in geometry: GeometryProxy) -> CGFloat {
        let boxWidth: CGFloat = 120
        let padding: CGFloat = 15
        
        guard let proxy = chartProxy,
              let xPosition = proxy.position(forX: frame.timestamp) else { return 0 }
        
        if xPosition > (geometry.size.width - boxWidth - padding) {
            return xPosition - boxWidth - padding
        }
        
        return xPosition + padding
    }
    
    private func calculateVerticalPosition(for frame: VMAFCalculator.FrameMetric, in geometry: GeometryProxy, proxy: ChartProxy) -> CGFloat {
        guard let yPosition = proxy.position(forY: frame.vmafScore) else { return 0 }
        let boxHeight: CGFloat = 80
        let padding: CGFloat = 10
        
        let desiredPosition = yPosition - (boxHeight / 2)
        return min(max(padding, desiredPosition), geometry.size.height - boxHeight - padding)
    }
}

// MARK: - Color Interpolation
extension Color {
    func interpolate(to other: Color, amount: Double) -> Color {
        let uiColor1 = NSColor(self)
        let uiColor2 = NSColor(other)
        
        let components1 = uiColor1.cgColor.components ?? [0, 0, 0, 1]
        let components2 = uiColor2.cgColor.components ?? [0, 0, 0, 1]
        
        let r = components1[0] + (components2[0] - components1[0]) * amount
        let g = components1[1] + (components2[1] - components1[1]) * amount
        let b = components1[2] + (components2[2] - components1[2]) * amount
        let a = components1[3] + (components2[3] - components1[3]) * amount
        
        return Color(NSColor(red: r, green: g, blue: b, alpha: a))
    }
}

#Preview {
    HeatMapView(frameMetrics: [
        VMAFCalculator.FrameMetric(
            frameNumber: 1,
            vmafScore: 85,
            integerMotion: 4.5,
            integerMotion2: 4.2,
            integerAdm2: 0.98,
            integerAdmScales: [0.96, 0.97, 0.98, 0.99],
            integerVifScales: [0.65, 0.97, 0.99, 0.99]
        ),
        VMAFCalculator.FrameMetric(
            frameNumber: 2,
            vmafScore: 87,
            integerMotion: 4.6,
            integerMotion2: 4.3,
            integerAdm2: 0.99,
            integerAdmScales: [0.97, 0.98, 0.99, 0.99],
            integerVifScales: [0.66, 0.98, 0.99, 0.99]
        ),
        VMAFCalculator.FrameMetric(
            frameNumber: 3,
            vmafScore: 86,
            integerMotion: 4.4,
            integerMotion2: 4.1,
            integerAdm2: 0.98,
            integerAdmScales: [0.96, 0.97, 0.98, 0.99],
            integerVifScales: [0.65, 0.97, 0.99, 0.99]
        )
    ])
} 