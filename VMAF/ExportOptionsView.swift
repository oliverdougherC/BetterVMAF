import SwiftUI
import AppKit

struct ExportOptionsView: View {
    let result: VMAFCalculator.VMAFResult
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportManager.ExportFormat = .pdf
    @State private var options = ExportManager.ExportOptions()
    @State private var isExporting = false
    @State private var choosingDestination = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @State private var exportWorker: Task<Void, Error>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export comparison").font(.title2.bold())
            Picker("Format", selection: $selectedFormat) {
                Text("Summary PDF").tag(ExportManager.ExportFormat.pdf)
                Text("CSV").tag(ExportManager.ExportFormat.csv)
                Text("JSON").tag(ExportManager.ExportFormat.json)
            }.pickerStyle(.segmented).disabled(isExporting)
            Toggle("Include every frame", isOn: $options.includeFrameData).disabled(isExporting)
            Toggle("Include aggregate measurements", isOn: $options.includeAggregateMetrics).disabled(isExporting)
            if selectedFormat == .pdf {
                Toggle("Include VMAF timeline", isOn: $options.includeGraphs).disabled(isExporting)
                Text("PDF defaults to one summary page. Detailed PDF is limited to 500 frames; use CSV or JSON for full long-video data.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Immutable file identities, metric definitions, configuration and coverage are always included. JSON with both options selected preserves the complete analysis schema.").font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button(isExporting ? "Cancel export" : "Cancel") {
                    if isExporting { exportWorker?.cancel(); task?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction)
                Spacer()
                if isExporting { ProgressView().controlSize(.small) }
                Button("Choose destination…", action: exportData).buttonStyle(.borderedProminent)
                    .disabled(isExporting || choosingDestination).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 480)
        .onChange(of: selectedFormat) { _, format in options.includeFrameData = format != .pdf }
        .onDisappear { exportWorker?.cancel(); task?.cancel() }
        .interactiveDismissDisabled(isExporting)
    }
    @MainActor private func exportData() {
        guard !isExporting, !choosingDestination else { return }
        choosingDestination = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [selectedFormat.contentType]
        panel.nameFieldStringValue = "comparison.\(selectedFormat.fileExtension)"
        // Destination first: canceling the panel never starts serialization.
        panel.begin { response in
            choosingDestination = false
            guard response == .OK, let destination = panel.url else { return }
            isExporting = true
            errorMessage = nil
            let format = selectedFormat
            let snapshot = options
            let worker = Task.detached(priority: .utility) {
                try ExportManager().write(result: result, format: format, options: snapshot, to: destination)
            }
            exportWorker = worker
            task = Task {
                do {
                    try await worker.value
                    if Task.isCancelled { errorMessage = "Export finished before cancellation. The complete report was saved." }
                    else { dismiss() }
                }
                catch is CancellationError { errorMessage = "Export cancelled. No partial report was saved." }
                catch { errorMessage = error.localizedDescription }
                isExporting = false
                exportWorker = nil
                task = nil
            }
        }
    }
}
