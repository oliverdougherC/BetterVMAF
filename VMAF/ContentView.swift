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
    
    private let calculator = VMAFCalculator()
    
    var body: some View {
        VStack(spacing: 24) {
            ScrollView {
                VStack(spacing: 24) {
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
                            Text("Results")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ResultRow(title: "VMAF Score", value: result.score)
                                ResultRow(title: "Range", value: "\(String(format: "%.2f", result.minScore)) to \(String(format: "%.2f", result.maxScore))")
                                ResultRow(title: "Harmonic Mean", value: result.harmonicMean)
                            }
                            
                            // Graph View
                            VMAFGraphView(frameMetrics: result.frameMetrics)
                                .frame(minHeight: 500)
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
        .frame(minWidth: 800, minHeight: 800)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func selectVideo(for keyPath: ReferenceWritableKeyPath<VMAFView, URL?>) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie]
        
        if panel.runModal() == .OK, let url = panel.url {
            self[keyPath: keyPath] = url
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
