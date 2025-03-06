import SwiftUI

struct ExportOptionsView: View {
    let result: VMAFCalculator.VMAFResult
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFormat: ExportManager.ExportFormat = .csv
    @State private var options = ExportManager.ExportOptions()
    @State private var isExporting = false
    @State private var errorMessage: String?
    
    private let exportManager = ExportManager()
    
    var body: some View {
        VStack(spacing: 16) {
            // Format Selection
            Picker("Export Format", selection: $selectedFormat) {
                Text("CSV").tag(ExportManager.ExportFormat.csv)
                Text("JSON").tag(ExportManager.ExportFormat.json)
                Text("PDF").tag(ExportManager.ExportFormat.pdf)
            }
            .pickerStyle(.segmented)
            
            // Options
            GroupBox("Export Options") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Include Frame Data", isOn: $options.includeFrameData)
                    Toggle("Include Aggregate Metrics", isOn: $options.includeAggregateMetrics)
                    Toggle("Include Graphs", isOn: .init(
                        get: { selectedFormat == .pdf ? options.includeGraphs : false },
                        set: { options.includeGraphs = $0 }
                    ))
                    .disabled(selectedFormat != .pdf)
                }
                .padding(8)
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: exportData) {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Export")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    @MainActor
    private func exportData() {
        isExporting = true
        errorMessage = nil
        
        Task {
            do {
                // First generate the export data
                let exportData = try exportManager.export(
                    result: result,
                    format: selectedFormat,
                    options: options
                )
                
                // Show save panel on main thread
                let panel = NSSavePanel()
                panel.allowedContentTypes = [selectedFormat.contentType]
                panel.nameFieldStringValue = "vmaf_results.\(selectedFormat.fileExtension)"
                
                if panel.runModal() == .OK, let saveURL = panel.url {
                    try exportData.write(to: saveURL)
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isExporting = false
        }
    }
}

#Preview {
    ExportOptionsView(result: VMAFCalculator.VMAFResult(
        score: 95.5,
        minScore: 90.0,
        maxScore: 100.0,
        harmonicMean: 94.8,
        frameMetrics: [],
        duration: 10.0,
        frameCount: 300
    ))
} 