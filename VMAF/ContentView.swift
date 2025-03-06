//
//  ContentView.swift
//  VMAF
//
//  Created by Oliver Dougherty on 3/4/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        VMAFView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VMAFView: View {
    @State private var referenceVideo: URL?
    @State private var comparisonVideo: URL?
    @State private var vmafResult: VMAFCalculator.VMAFResult?
    @State private var isCalculating = false
    @State private var errorMessage: String?
    @State private var showGraph = false  // Graph hidden by default
    @State private var visualizationType: VisualizationType = .line
    @State private var showExportOptions = false
    
    private let calculator = VMAFCalculator()
    
    enum VisualizationType {
        case line
        case heatmap
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Better VMAF")
                        .font(.title)
                        .padding(.top)
                    
                    // Video Selection Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Video Selection")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        // Reference Video Selection
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reference Video")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if let url = referenceVideo {
                                    Text(url.lastPathComponent)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                } else {
                                    Text("Not Selected")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(action: { selectVideo(for: \VMAFView.referenceVideo) }) {
                                Label("Select", systemImage: "doc.badge.plus")
                                    .font(.system(.body, design: .rounded))
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        
                        // Comparison Video Selection
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Comparison Video")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if let url = comparisonVideo {
                                    Text(url.lastPathComponent)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                } else {
                                    Text("Not Selected")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(action: { selectVideo(for: \VMAFView.comparisonVideo) }) {
                                Label("Select", systemImage: "doc.badge.plus")
                                    .font(.system(.body, design: .rounded))
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    
                    // Calculate Button
                    Button(action: calculateVMAF) {
                        if isCalculating {
                            ProgressView()
                                .controlSize(.large)
                        } else {
                            Label("Calculate VMAF", systemImage: "chart.bar.fill")
                                .font(.system(.body, design: .rounded))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(referenceVideo == nil || comparisonVideo == nil || isCalculating)
                    .controlSize(.large)
                    
                    // Results Section
                    if let result = vmafResult {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Results")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Button(action: {
                                        if showGraph && visualizationType == .line {
                                            // If this button is active, deactivate it
                                            showGraph = false
                                        } else {
                                            // Activate this button and deactivate the other
                                            showGraph = true
                                            visualizationType = .line
                                        }
                                    }) {
                                        Label("Show Graph", systemImage: "chart.xyaxis.line")
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .background(showGraph && visualizationType == .line ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                    .foregroundColor(showGraph && visualizationType == .line ? .white : .primary)
                                    .cornerRadius(6)
                                    .controlSize(.small)
                                    
                                    Button(action: {
                                        if showGraph && visualizationType == .heatmap {
                                            // If this button is active, deactivate it
                                            showGraph = false
                                        } else {
                                            // Activate this button and deactivate the other
                                            showGraph = true
                                            visualizationType = .heatmap
                                        }
                                    }) {
                                        Label("Show Heat Map", systemImage: "chart.bar.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .background(showGraph && visualizationType == .heatmap ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                    .foregroundColor(showGraph && visualizationType == .heatmap ? .white : .primary)
                                    .cornerRadius(6)
                                    .controlSize(.small)
                                    
                                    Divider()
                                        .frame(height: 16)
                                    
                                    Button(action: { showExportOptions = true }) {
                                        Label("Export", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                                    .controlSize(.small)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ResultRow(title: "VMAF Score", value: result.score)
                                ResultRow(title: "Range", value: "\(String(format: "%.2f", result.minScore)) to \(String(format: "%.2f", result.maxScore))")
                                ResultRow(title: "Harmonic Mean", value: result.harmonicMean)
                            }
                            
                            // Graph View (only shown when toggled)
                            if showGraph {
                                if visualizationType == .line {
                                    VMAFGraphView(frameMetrics: result.frameMetrics)
                                        .frame(minHeight: 300, maxHeight: 500)
                                } else {
                                    HeatMapView(frameMetrics: result.frameMetrics)
                                        .frame(minHeight: 300, maxHeight: 500)
                                }
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 400)  // Reduced minimum size
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showExportOptions) {
            ExportOptionsView(result: vmafResult!)
        }
    }
    
    private func selectVideo(for keyPath: ReferenceWritableKeyPath<VMAFView, URL?>) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie]
        
        if panel.runModal() == .OK, let url = panel.url {
            self[keyPath: keyPath] = url
            
            // Store the path for PDF export
            if keyPath == \VMAFView.referenceVideo {
                UserDefaults.standard.set(url, forKey: "LastReferenceVideo")
            } else if keyPath == \VMAFView.comparisonVideo {
                UserDefaults.standard.set(url, forKey: "LastComparisonVideo")
            }
        }
    }
    
    private func calculateVMAF() {
        guard let reference = referenceVideo,
              let comparison = comparisonVideo else { return }
        
        isCalculating = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await calculator.calculateVMAF(
                    referenceVideo: reference,
                    comparisonVideo: comparison
                )
                await MainActor.run {
                    self.vmafResult = result
                    self.isCalculating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isCalculating = false
                }
            }
        }
    }
}

struct ResultRow: View {
    let title: String
    let value: Any
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            if let doubleValue = value as? Double {
                Text(String(format: "%.2f", doubleValue))
                    .font(.system(.body, design: .monospaced))
            } else if let stringValue = value as? String {
                Text(stringValue)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }
}

#Preview {
    VMAFView()
} 
