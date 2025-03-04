//
//  ContentView.swift
//  VMAF
//
//  Created by Oliver Dougherty on 3/4/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct VMAFView: View {
    @State private var referenceVideo: URL?
    @State private var comparisonVideo: URL?
    @State private var vmafResult: VMAFCalculator.VMAFResult?
    @State private var isCalculating = false
    @State private var errorMessage: String?
    
    private let calculator = VMAFCalculator()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("VMAF Calculator")
                .font(.title)
                .padding()
            
            // Reference Video Selection
            HStack {
                Text("Reference Video:")
                Spacer()
                if let url = referenceVideo {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                } else {
                    Text("Not Selected")
                        .foregroundColor(.secondary)
                }
                Button("Select") {
                    selectVideo(for: \VMAFView.referenceVideo)
                }
            }
            
            // Comparison Video Selection
            HStack {
                Text("Comparison Video:")
                Spacer()
                if let url = comparisonVideo {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                } else {
                    Text("Not Selected")
                        .foregroundColor(.secondary)
                }
                Button("Select") {
                    selectVideo(for: \VMAFView.comparisonVideo)
                }
            }
            
            // Calculate Button
            Button(action: calculateVMAF) {
                if isCalculating {
                    ProgressView()
                } else {
                    Text("Calculate VMAF")
                }
            }
            .disabled(referenceVideo == nil || comparisonVideo == nil || isCalculating)
            
            // Results
            if let result = vmafResult {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Results:")
                        .font(.headline)
                    Text("VMAF Score: \(String(format: "%.2f", result.score))")
                    Text("Range: \(String(format: "%.2f", result.minScore)) to \(String(format: "%.2f", result.maxScore))")
                    Text("Harmonic Mean: \(String(format: "%.2f", result.harmonicMean))")
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
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

#Preview {
    VMAFView()
} 
