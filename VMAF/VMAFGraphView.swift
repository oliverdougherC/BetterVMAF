import SwiftUI
import Charts

struct VMAFGraphView: View {
    let frameMetrics: [VMAFCalculator.FrameMetric]
    @State private var selectedTimeRange: ClosedRange<TimeInterval>?
    @State private var isZoomed = false
    @State private var zoomLevel: Double = 1.0
    @State private var scrollPosition: TimeInterval = 0
    @State private var hoveredFrame: VMAFCalculator.FrameMetric?
    @State private var chartProxy: ChartProxy?
    @State private var sliderPosition: Double = 0
    
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
        // Round down to nearest 10 and subtract 5 for buffer
        let minY = max(0.0, floor((minScore - 5.0) / 10.0) * 10.0)
        // Add just 0.5 point of padding above 100
        return minY...100.5
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Chart with optional hover details
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // Chart
                    Chart(filteredMetrics) { metric in
                        // Background grid lines
                        ForEach([10, 20, 30, 40, 50, 60, 70, 80, 90, 100], id: \.self) { value in
                            RuleMark(y: .value("Grid", value))
                                .foregroundStyle(.gray.opacity(0.1))
                        }
                        
                        // Data line
                        LineMark(
                            x: .value("Time", metric.timestamp),
                            y: .value("VMAF", metric.vmafScore)
                        )
                        .foregroundStyle(.blue)
                        
                        // Interactive points
                        PointMark(
                            x: .value("Time", metric.timestamp),
                            y: .value("VMAF", metric.vmafScore)
                        )
                        .foregroundStyle(hoveredFrame?.frameNumber == metric.frameNumber ? .blue : .blue.opacity(0.3))
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
                                    .font(.system(size: 9))  // Smaller font
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .stride(by: 10)) { value in
                            if let score = value.as(Double.self) {
                                AxisValueLabel(String(format: "%.0f", score))
                                    .font(.system(size: 9))  // Smaller font
                            }
                            AxisGridLine()
                                .foregroundStyle(.gray.opacity(0.1))
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onAppear {
                                    chartProxy = proxy
                                }
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        if let (frame, distance) = findNearestFrame(at: location, in: geometry, proxy: proxy),
                                           distance < 10 { // Only select if within 10 points of the dot
                                            withAnimation(.easeOut(duration: 0.1)) {
                                                hoveredFrame = frame
                                            }
                                        } else {
                                            withAnimation(.easeOut(duration: 0.1)) {
                                                hoveredFrame = nil
                                            }
                                        }
                                    case .ended:
                                        withAnimation(.easeOut(duration: 0.1)) {
                                            hoveredFrame = nil
                                        }
                                    }
                                }
                        }
                    }
                    
                    // Hover details popup
                    if let frame = hoveredFrame, let proxy = chartProxy {
                        GeometryReader { geometry in
                            frameDetailsView(frame: frame)
                                .padding(4)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(4)
                                .shadow(radius: 2)
                                .offset(x: calculateHoverBoxOffset(for: frame, in: geometry),
                                        y: calculateVerticalPosition(for: frame, in: geometry, proxy: proxy))
                                .animation(.easeOut(duration: 0.1), value: frame.frameNumber)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
            .frame(minHeight: 120, maxHeight: .infinity)
            
            // Info and controls
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
                
                Text("Metrics: \(frameMetrics.count) (\(filteredMetrics.count) visible)")
                    .font(.system(size: 10))
                
                if isZoomed {
                    Text("Zoom: \(String(format: "%.1fx", zoomLevel))")
                        .font(.system(size: 10))
                }
                
                Spacer()
                
                Text("Average VMAF: \(String(format: "%.1f", calculateAverageVMAF()))")
                    .font(.system(size: 10))
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
                        LineMark(
                            x: .value("Time", metric.timestamp),
                            y: .value("VMAF", metric.vmafScore)
                        )
                        .foregroundStyle(.blue.opacity(0.3))
                    }
                    .chartXScale(domain: timeRange)
                    .chartYScale(domain: yAxisRange)
                    .frame(height: 20)
                    .overlay(
                        GeometryReader { geometry in
                            let visibleWidth = geometry.size.width / zoomLevel
                            let xOffset = geometry.size.width * (scrollPosition - timeRange.lowerBound) / (timeRange.upperBound - timeRange.lowerBound)
                            Rectangle()
                                .fill(.blue.opacity(0.2))
                                .frame(width: visibleWidth)
                                .offset(x: xOffset)
                        }
                    )
                    
                    // Slider
                    Slider(
                        value: Binding(
                            get: {
                                (scrollPosition - timeRange.lowerBound) / (timeRange.upperBound - timeRange.lowerBound)
                            },
                            set: { newValue in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    let totalDuration = timeRange.upperBound - timeRange.lowerBound
                                    scrollPosition = timeRange.lowerBound + totalDuration * newValue
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
    
    private func frameDetailsView(frame: VMAFCalculator.FrameMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {  // Reduced spacing
            Text("Frame \(frame.frameNumber)")
                .font(.system(size: 10, weight: .bold))
            Text("VMAF: \(String(format: "%.2f", frame.vmafScore))")
            Text("Time: \(formatTime(frame.timestamp))")
            Text("Motion: \(String(format: "%.2f", frame.integerMotion))")
            Text("ADM2: \(String(format: "%.2f", frame.integerAdm2))")
        }
        .font(.system(size: 9))  // Smaller font
        .fixedSize(horizontal: true, vertical: true)
    }
    
    private func findNearestFrame(at location: CGPoint, in geometry: GeometryProxy, proxy: ChartProxy) -> (VMAFCalculator.FrameMetric, CGFloat)? {
        let xPosition = location.x - geometry.frame(in: .local).origin.x
        let yPosition = location.y - geometry.frame(in: .local).origin.y
        
        // Check if the position is valid within the chart
        guard (proxy.value(atX: xPosition) as TimeInterval?) != nil,
              (proxy.value(atY: yPosition) as Double?) != nil else { return nil }
        
        return filteredMetrics
            .map { metric -> (VMAFCalculator.FrameMetric, CGFloat) in
                guard let metricX = proxy.position(forX: metric.timestamp),
                      let metricY = proxy.position(forY: metric.vmafScore) else {
                    return (metric, .infinity)
                }
                
                let distance = sqrt(pow(metricX - xPosition, 2) + pow(metricY - yPosition, 2))
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
    
    private func calculateAverageVMAF() -> Double {
        guard !filteredMetrics.isEmpty else { return 0 }
        let sum = filteredMetrics.reduce(0) { $0 + $1.vmafScore }
        return sum / Double(filteredMetrics.count)
    }
    
    private func calculateHoverBoxOffset(for frame: VMAFCalculator.FrameMetric, in geometry: GeometryProxy) -> CGFloat {
        let boxWidth: CGFloat = 120
        let padding: CGFloat = 5
        
        guard let proxy = chartProxy,
              let xPosition = proxy.position(forX: frame.timestamp) else { return 0 }
        
        // If the box would go off the right edge, place it to the left of the cursor
        if xPosition > (geometry.size.width - boxWidth - padding) {
            return xPosition - boxWidth - padding
        }
        
        // Otherwise, place it to the right of the cursor
        return xPosition + padding
    }
    
    private func calculateVerticalPosition(for frame: VMAFCalculator.FrameMetric, in geometry: GeometryProxy, proxy: ChartProxy) -> CGFloat {
        guard let yPosition = proxy.position(forY: frame.vmafScore) else { return 0 }
        let boxHeight: CGFloat = 80  // Reduced height
        
        // Ensure the box stays within the chart's bounds and closer to the point
        return min(max(0, yPosition - boxHeight/2), geometry.size.height - boxHeight)
    }
}

#Preview {
    VMAFGraphView(frameMetrics: [
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