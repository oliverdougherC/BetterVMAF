import SwiftUI
import Charts

struct VMAFGraphView: View {
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
                                    .font(.system(size: 9))
                            }
                            AxisGridLine()
                                .foregroundStyle(.clear)  // Hide X-axis grid lines
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
                    .chartLegend(.hidden)  // Hide the legend
                    .chartXAxisLabel("")   // Remove X axis label
                    .chartYAxisLabel("")   // Remove Y axis label
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
                                        
                                        // Cancel existing timer
                                        hoverDebounceTimer?.invalidate()
                                        
                                        // Create new timer for debouncing
                                        hoverDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
                                            if let (frame, distance) = findNearestFrame(at: location, in: geometry, proxy: proxy),
                                               distance < 30 { // Increased detection area and simplified distance calculation
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
                
                Text("Metrics: \(frameMetrics.count)")
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
                
                if isZoomed {
                    Text("Visible VMAF: \(String(format: "%.1f", calculateVisibleVMAF()))")
                        .font(.system(size: 10))
                } else {
                    Text("Average VMAF: \(String(format: "%.1f", calculateTotalVMAF()))")
                        .font(.system(size: 10))
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
                        LineMark(
                            x: .value("Time", metric.timestamp),
                            y: .value("VMAF", metric.vmafScore)
                        )
                        .foregroundStyle(.blue.opacity(0.3))
                    }
                    .chartXScale(domain: timeRange)
                    .chartYScale(domain: yAxisRange)
                    .chartXAxis(.hidden)  // Hide X axis completely
                    .chartYAxis(.hidden)  // Hide Y axis completely
                    .chartLegend(.hidden) // Hide legend
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
        let xPosition = location.x
        let yPosition = location.y
        
        // Get the chart area bounds
        let chartFrame = geometry.frame(in: .local)
        
        // Ensure the cursor is within the chart bounds
        guard chartFrame.contains(CGPoint(x: xPosition, y: yPosition)) else { return nil }
        
        // Convert screen coordinates to data values
        guard let _ = proxy.value(atX: xPosition) as TimeInterval?,
              let _ = proxy.value(atY: yPosition) as Double? else { return nil }
        
        // Find the nearest frame primarily based on X-axis distance
        return filteredMetrics
            .map { metric -> (VMAFCalculator.FrameMetric, CGFloat) in
                guard let metricX = proxy.position(forX: metric.timestamp) else {
                    return (metric, .infinity)
                }
                
                // Prioritize X-axis distance more than Y-axis distance
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
    
    private func calculateVisibleVMAF() -> Double {
        guard !filteredMetrics.isEmpty else { return 0 }
        let sum = filteredMetrics.reduce(0) { $0 + $1.vmafScore }
        return sum / Double(filteredMetrics.count)
    }
    
    private func calculateTotalVMAF() -> Double {
        guard !frameMetrics.isEmpty else { return 0 }
        let sum = frameMetrics.reduce(0) { $0 + $1.vmafScore }
        return sum / Double(frameMetrics.count)
    }
    
    private func calculateHoverBoxOffset(for frame: VMAFCalculator.FrameMetric, in geometry: GeometryProxy) -> CGFloat {
        let boxWidth: CGFloat = 120
        let padding: CGFloat = 15  // Increased consistent padding
        
        guard let proxy = chartProxy,
              let xPosition = proxy.position(forX: frame.timestamp) else { return 0 }
        
        // Always place the box to the right of the point unless it would go off screen
        if xPosition > (geometry.size.width - boxWidth - padding) {
            return xPosition - boxWidth - padding
        }
        
        return xPosition + padding
    }
    
    private func calculateVerticalPosition(for frame: VMAFCalculator.FrameMetric, in geometry: GeometryProxy, proxy: ChartProxy) -> CGFloat {
        guard let yPosition = proxy.position(forY: frame.vmafScore) else { return 0 }
        let boxHeight: CGFloat = 80
        let padding: CGFloat = 10  // Added consistent vertical padding
        
        // Keep the box vertically aligned with the point but ensure it stays within bounds
        let desiredPosition = yPosition - (boxHeight / 2)
        return min(max(padding, desiredPosition), geometry.size.height - boxHeight - padding)
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