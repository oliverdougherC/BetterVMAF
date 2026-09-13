import SwiftUI

/// Compatibility surface for older report callers. This is a temporal metric plot.
struct HeatMapView: View {
    let frameMetrics: [VMAFCalculator.FrameMetric]
    var body: some View {
        VMAFGraphView(frameMetrics: frameMetrics)
    }
}
