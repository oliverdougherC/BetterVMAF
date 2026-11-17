//
//  VMAFBatchView.swift
//  VMAF
//
//  Batch mode UI for running multiple comparisons against a single reference.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct VMAFBatchView: View {
    @State private var referenceVideo: URL?
    @State private var comparisons: [BatchItem] = []
    @ObservedObject private var activity = ComparisonActivity.shared
    @State private var activeRun: ComparisonRun?
    @State private var isCancelling = false
    private var isRunning: Bool { activeRun != nil }
    @State private var validationMessage: String?
    @State private var batchError: String?
    @State private var showCommandSheet = false
    @State private var ffmpegCommand: String = ""
    @State private var currentID: UUID?
    
    private let calculator = VMAFCalculator()
    
    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Batch Mode")
                        .font(.title)
                        .padding(.top)
                    
                    GroupBox("Reference Video") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reference Video (Original)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if let url = referenceVideo {
                                    Text(url.lastPathComponent)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                } else {
                                    Text("Not Selected")
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(action: selectReference) {
                                Label("Select", systemImage: "doc.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }
                    }
                    
                    GroupBox("Comparison Videos") {
                        VStack(alignment: .leading, spacing: 8) {
                            if comparisons.isEmpty {
                                Text("No comparison videos selected.")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(comparisons) { item in
                                    BatchItemRow(
                                        item: item,
                                        isCurrent: currentID == item.id,
                                        removeAction: { removeComparison(item) },
                                        canRemove: !isRunning
                                    )
                                }
                            }
                            
                            HStack {
                                Button(action: addComparisons) {
                                    Label("Add Videos", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRunning)
                                
                                if !comparisons.isEmpty && !isRunning {
                                    Button(action: { comparisons.removeAll() }) {
                                        Label("Clear", systemImage: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    
                    if let validation = validationMessage {
                        Text(validation)
                            .foregroundColor(.orange)
                            .font(.callout)
                    }
                    
                    if let batchError = batchError {
                        Text(batchError)
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                    
                    HStack {
                        Button(action: startBatch) {
                            if isRunning {
                                ProgressView()
                            } else {
                                Label("Start Batch", systemImage: "play.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(referenceVideo == nil || comparisons.isEmpty || isRunning || !activity.canStart)
                        
                        if isRunning {
                            Button(action: cancelBatch) {
                                Label("Cancel", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isCancelling)
                        }
                        
                        Spacer()
                        
                        if isRunning {
                            Button("Show FFmpeg Command") {
                                ffmpegCommand = calculator.getLastCommand()
                                showCommandSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showCommandSheet) {
            VStack(spacing: 16) {
                Text("FFmpeg Command")
                    .font(.headline)
                ScrollView {
                    Text(ffmpegCommand)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                
                Button("Close") {
                    showCommandSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(width: 600, height: 300)
        }
    }
    
    private func selectReference() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie]
        
        if panel.runModal() == .OK, let url = panel.url {
            referenceVideo = url
        }
    }
    
    private func addComparisons() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie]
        
        if panel.runModal() == .OK {
            let newItems = panel.urls.map { BatchItem(url: $0) }
            comparisons.append(contentsOf: newItems)
        }
    }
    
    private func removeComparison(_ item: BatchItem) {
        comparisons.removeAll { $0.id == item.id }
    }
    
    private func startBatch() {
        guard let reference = referenceVideo, activeRun == nil else { return }
        let pendingItems = comparisons.filter { $0.status != .completed }
        guard !pendingItems.isEmpty else {
            validationMessage = "No pending videos to process."
            return
        }
        guard let run = activity.begin() else { return }
        activeRun = run
        validationMessage = nil
        batchError = nil
        calculator.delegate = self

        Task {
            defer {
                currentID = nil
                activeRun = nil
                isCancelling = false
                activity.end(run)
            }

            let validation = await validate(reference: reference, comparisons: pendingItems.map(\.url), run: run)
            guard !run.isCancelled else { return }
            guard validation.isEmpty else {
                validationMessage = validation.joined(separator: "\n")
                return
            }
            for item in pendingItems {
                guard !run.isCancelled else { break }
                guard let index = comparisons.firstIndex(where: { $0.id == item.id }) else { continue }
                currentID = item.id
                comparisons[index].status = .running
                comparisons[index].progressFrames = 0
                comparisons[index].totalFrames = nil
                comparisons[index].percent = 0
                comparisons[index].fps = 0
                comparisons[index].result = nil
                comparisons[index].error = nil

                do {
                    let result = try await calculator.calculateVMAF(
                        referenceVideo: reference, comparisonVideo: item.url, run: run
                    )
                    try run.checkCancellation()
                    comparisons[index].status = .completed
                    comparisons[index].result = result
                    comparisons[index].percent = 100
                    comparisons[index].progressFrames = result.frameCount
                    comparisons[index].totalFrames = result.frameCount
                } catch {
                    if run.isCancelled {
                        comparisons[index].status = .pending
                        return
                    }
                    comparisons[index].status = .failed
                    comparisons[index].error = error.localizedDescription
                    batchError = "One or more comparisons failed. Check the list for details."
                }
            }
        }
    }

    private func cancelBatch() {
        isCancelling = true
        activeRun?.cancel()
    }

    private func validate(reference: URL, comparisons: [URL], run: ComparisonRun) async -> [String] {
        var issues: [String] = []
        guard let referenceProps = try? await videoProps(for: reference) else {
            issues.append("Reference video is unreadable or has no video track.")
            return issues
        }
        
        for url in comparisons {
            guard !run.isCancelled else { break }
            guard let props = try? await videoProps(for: url) else {
                issues.append("\(url.lastPathComponent): unreadable or no video track.")
                continue
            }
            if props.width != referenceProps.width || props.height != referenceProps.height {
                issues.append("\(url.lastPathComponent): resolution \(props.width)x\(props.height) does not match reference \(referenceProps.width)x\(referenceProps.height).")
            }
        }
        
        return issues
    }
    
    private func videoProps(for url: URL) async throws -> (width: Int, height: Int, fps: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw NSError(domain: "BatchValidation", code: 1, userInfo: nil)
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformedSize = naturalSize.applying(transform)
        let width = Int(round(abs(transformedSize.width)))
        let height = Int(round(abs(transformedSize.height)))
        let fps = Double(try await track.load(.nominalFrameRate))
        return (width, height, fps)
    }
}

// MARK: - Delegate
extension VMAFBatchView: VMAFCalculator.VMAFCalculatorDelegate {
    func vmafCalculatorDidUpdateProgress(frameCount: Int, fps: Double, progress: Double, totalFrames: Int) {
        guard let currentID, let idx = comparisons.firstIndex(where: { $0.id == currentID }) else { return }
        comparisons[idx].progressFrames = frameCount
        comparisons[idx].totalFrames = totalFrames > 0 ? totalFrames : comparisons[idx].totalFrames
        if let total = comparisons[idx].totalFrames, total > 0 {
            comparisons[idx].percent = min(100, max(0, Double(frameCount) / Double(total) * 100))
        } else {
            comparisons[idx].percent = progress
        }
        comparisons[idx].fps = fps
    }
}

// MARK: - Batch Item Row
private struct BatchItemRow: View {
    let item: BatchItem
    let isCurrent: Bool
    let removeAction: () -> Void
    let canRemove: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.url.lastPathComponent)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
                Spacer()
                if canRemove {
                    Button(action: removeAction) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            if isCurrent || item.status == .running || item.status == .completed || item.status == .failed {
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
                HStack(spacing: 12) {
                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if item.fps > 0 {
                        Text("\(String(format: "%.1f", item.fps)) FPS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let result = item.result, item.status == .completed {
                Text(String(format: "VMAF: %.2f  (min: %.2f  max: %.2f)", result.score, result.minScore, result.maxScore))
                    .font(.caption)
            }
            
            if let error = item.error, item.status == .failed {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
    
    private var statusLabel: String {
        switch item.status {
        case .pending: return "Pending"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch item.status {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private var progressValue: Double {
        if item.percent > 0 {
            return item.percent / 100.0
        }
        if let total = item.totalFrames, total > 0 {
            return Double(item.progressFrames) / Double(total)
        }
        return 0
    }
    
    private var progressText: String {
        if let total = item.totalFrames, total > 0 {
            let percent = min(100, max(0, Double(item.progressFrames) / Double(total) * 100))
            return "Frame \(item.progressFrames) of \(total) (\(String(format: "%.1f%%", percent)))"
        }
        return "Frame \(item.progressFrames)"
    }
}

// MARK: - Models
struct BatchItem: Identifiable {
    enum Status {
        case pending
        case running
        case completed
        case failed
    }
    
    let id = UUID()
    let url: URL
    var status: Status = .pending
    var progressFrames: Int = 0
    var totalFrames: Int? = nil
    var percent: Double = 0
    var fps: Double = 0
    var result: VMAFCalculator.VMAFResult? = nil
    var error: String? = nil
}

