import SwiftUI

struct ComparisonResultView: View {
    let result: VMAFCalculator.VMAFResult
    var onInspect: (() -> Void)? = nil
    @StateObject private var playback = PlaybackController()
    @State private var summary: ReviewSummary?
    @State private var showExport = false
    @State private var selectedConcern: String?
    @State private var provenance = ""
    @State private var selectedMetric = "vmaf"
    @State private var timeline: [TimelinePoint] = []
    @State private var showAllConcerns = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Review this comparison").font(.title2.bold())
                Spacer()
                Button("Export…", systemImage: "square.and.arrow.up") { showExport = true }
            }
            if let analysis = result.analysis {
                Text("\(analysis.reference.filename) → \(analysis.comparison.filename)").font(.headline).textSelection(.enabled)
                savings(analysis)
                primaryMeasurements(analysis)
                Text("\(analysis.samples.count) matched frames · \(analysis.configuration.coverage) analysis · \(analysis.modelIdentifier)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PlaybackComparisonView(controller: playback, result: result).id("viewer-\(result.analysis?.runID.uuidString ?? "legacy")")
            Text("Moments to review").font(.headline)
            if let summary {
                if summary.concerns.isEmpty {
                    Text("No localized metric concern was selected. Inspect motion and detail; this does not establish visual transparency.").foregroundStyle(.secondary)
                }
                ForEach(showAllConcerns ? summary.concerns : Array(summary.concerns.prefix(6))) { concern in
                    Button {
                        selectedConcern = concern.id
                        playback.select(start: concern.start, end: concern.end)
                        onInspect?()
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: "play.rectangle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "%.3f–%.3f s · %@", concern.start, concern.end, concern.kind)).fontWeight(.medium)
                                Text(concern.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(10).background(selectedConcern == concern.id ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityHint("Seek both videos to the exact matched interval and enable looping")
                }
                if summary.concerns.count > 6 {
                    Button(showAllConcerns ? "Show fewer moments" : "Show all \(summary.concerns.count) moments") { showAllConcerns.toggle() }
                }
            } else { ProgressView("Preparing review intervals…").controlSize(.small) }
            if let analysis = result.analysis {
                Picker("Timeline measurement", selection: $selectedMetric) {
                    ForEach(analysis.definitions, id: \.id) { Text($0.name).tag($0.id) }
                }
                if let definition = analysis.definitions.first(where: { $0.id == selectedMetric }) {
                    MetricTimelineView(points: timeline, name: definition.name, unit: definition.unit,
                        revision: analysis.runID, selectedTime: playback.timestamp, onSeek: { playback.seek(time: $0) })
                        .id(selectedMetric).frame(height: 230)
                    Text("\(definition.direction == "lower" ? "Lower values indicate less measured banding." : "Higher values indicate greater measured source fidelity.") Nonfinite and unavailable values remain in the record and are omitted from the numeric line.").font(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Measurements and viewing assumptions") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Metrics retain their own scales and directions. Supplementary duration-weighted distributions are separate from upstream pooling.").font(.caption).foregroundStyle(.secondary)
                    if let analysis = result.analysis {
                        ForEach(analysis.definitions, id: \.id) { metric in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(metric.name) · \(metric.unit) · \(metric.direction)").fontWeight(.medium)
                                Text("Version \(metric.version) · \(metric.pooling)").font(.caption).foregroundStyle(.secondary)
                                if let value = ComparisonTradeoffs.nativeValue(metric.id, in: analysis) { Text("Upstream aggregate: \(ExportManager.value(value))").monospacedDigit() }
                                if let distribution = summary?.distributions.first(where: { $0.metricID == metric.id }) {
                                    Text("Median \(ExportManager.value(distribution.median)) · \(distribution.tailLabel) \(ExportManager.value(distribution.tail)) · extreme \(ExportManager.value(distribution.extreme))").font(.caption).monospacedDigit()
                                    Text("\(distribution.validCount) valid / \(distribution.missingCount) missing samples").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text(analysis.configuration.viewingProfile.label).font(.headline)
                        Text(analysis.configuration.colorPolicy).font(.caption)
                        Text(analysis.configuration.geometryPolicy).font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
            }
            DisclosureGroup("Reproducibility record") {
                ScrollView { Text(provenance).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 200)
            }
        }
        .task(id: result.analysis?.runID) {
            let worker = Task.detached(priority: .userInitiated) { ReviewSummary.make(result: result) }
            async let load: () = playback.load(result)
            let prepared = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { worker.cancel(); return }
            summary = prepared
            var options = ExportManager.ExportOptions(); options.includeFrameData = false
            provenance = (try? await Task.detached(priority: .utility) {
                String(decoding: try ExportManager().exportToJSON(result: result, options: options), as: UTF8.self)
            }.value) ?? "Provenance unavailable."
            await load
        }
        .task(id: "\(result.analysis?.runID.uuidString ?? "legacy")/\(selectedMetric)") {
            let key = selectedMetric
            guard let analysis = result.analysis else { return }
            let worker = Task.detached(priority: .userInitiated) {
                var points: [TimelinePoint] = []
                points.reserveCapacity(analysis.samples.count)
                var segment = 0
                for (index, sample) in analysis.samples.enumerated() {
                    if index % 4096 == 0 && Task.isCancelled { return [] as [TimelinePoint] }
                    if let value = sample.values[key]?.finiteValue {
                        points.append(TimelinePoint(id: sample.pair.index, time: sample.pair.timestamp, value: value, segment: segment))
                    } else { segment += 1 }
                }
                return points
            }
            let points = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            timeline = points
        }
        .onDisappear { playback.close() }
        .sheet(isPresented: $showExport) { ExportOptionsView(result: result) }
    }
    private func primaryMeasurements(_ analysis: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 28) {
                metric("VMAF v1 · upstream mean", ComparisonTradeoffs.nativeValue("vmaf", in: analysis), unit: "model score")
                metric("XPSNR · minimum native plane average", analysis.aggregateMetrics["xpsnr_min_plane"], unit: "dB")
            }
            Text("Banding diagnostic · source \(display(ComparisonTradeoffs.nativeValue("cambi_source", in: analysis))) → encode \(display(ComparisonTradeoffs.nativeValue("cambi_encode", in: analysis))) · introduced \(display(ComparisonTradeoffs.nativeValue("cambi_full_reference", in: analysis)))")
                .font(.callout).monospacedDigit()
            Text("CAMBI is also used by VMAF v1. Its source-aware difference is a diagnostic, not an independent extra vote or perfect causal attribution.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String, _ value: MetricValue?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(display(value)) \(unit)").font(.title3.bold()).monospacedDigit()
        }
    }
    private func display(_ value: MetricValue?) -> String {
        guard let value else { return "unavailable" }
        if let number = value.finiteValue { return String(format: "%.3f", number) }
        return ExportManager.value(value)
    }
    private func savings(_ analysis: AnalysisResult) -> some View {
        let saved = analysis.reference.byteCount - analysis.comparison.byteCount
        let percentage = analysis.reference.byteCount > 0 ? Double(saved) / Double(analysis.reference.byteCount) * 100 : 0
        return HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading) {
                Text("File size tradeoff").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%+.1f%% space saved", percentage)).font(.title3.bold())
                Text("\(ByteCountFormatter.string(fromByteCount: analysis.reference.byteCount, countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: analysis.comparison.byteCount, countStyle: .file))").font(.caption)
            }
            VStack(alignment: .leading) {
                Text("Container bitrate · includes audio/overhead").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.2f → %.2f Mb/s", Double(analysis.reference.byteCount) * 8 / max(analysis.comparedDuration, 0.001) / 1_000_000, Double(analysis.comparison.byteCount) * 8 / max(analysis.comparedDuration, 0.001) / 1_000_000)).monospacedDigit()
            }
        }
    }
}
