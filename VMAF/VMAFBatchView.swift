import SwiftUI

struct VMAFBatchView: View {
    @StateObject private var session = BatchComparisonSession()
    @State private var selectedID: UUID?
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("One source, several encodes").font(.largeTitle.bold())
                Text("Analyze sequentially, then inspect each candidate. Size and named measurements stay separate.").foregroundStyle(.secondary)
                VideoInputCard(title: "Shared source · original", url: session.source, disabled: session.isBusy) { url in
                    selectedID = nil; session.selectSource(url)
                }
                DisclosureGroup("Viewing assumptions for this queue") {
                    Picker("Viewing profile", selection: Binding(get: { session.configuration.viewingProfile }, set: { selectedID = nil; session.selectProfile($0) })) {
                        ForEach(AnalysisConfiguration.ViewingProfile.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.disabled(session.isBusy)
                }
                HStack {
                    Button("Add encodes…", systemImage: "plus") { VideoSelection.choose(multiple: true) { session.add($0) } }.disabled(session.isBusy)
                    Button("Start pending", action: session.start).buttonStyle(.borderedProminent)
                        .disabled(session.isBusy || session.source == nil || !session.items.contains(where: { $0.state == .pending }))
                    if session.isBusy {
                        ProgressView().controlSize(.small)
                        Button(session.state == .cancelling ? "Stopping…" : "Stop queue", action: session.cancel).disabled(session.state == .cancelling)
                    }
                    Spacer()
                    Button("Clear") { selectedID = nil; session.clear() }.disabled(session.isBusy || session.items.isEmpty)
                }
                Text("Sequential queue · up to 8 candidates and 1,000,000 retained frame samples.").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("batchResourceLimits")
                    .accessibilityLabel("Queue limits")
                    .accessibilityValue("Up to 8 candidates and 1,000,000 retained frame samples")
                if let message = session.queueMessage { Text(message).foregroundStyle(.orange) }
                if session.items.isEmpty { ContentUnavailableView("Add your encodes", systemImage: "tray", description: Text("Choose videos or drop them here. Each will be compared against the same source.")) }
                ForEach(session.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.url.lastPathComponent).font(.headline).lineLimit(1).help(item.url.path)
                            Spacer()
                            Text(item.state.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                            if item.result != nil {
                                Button("Inspect") { selectedID = item.id }
                            }
                            if session.isBusy && (item.state == .running || item.state == .pending) {
                                Button("Cancel job") { session.cancelItem(item.id) }
                            } else if !session.isBusy {
                                if item.state == .failed || item.state == .cancelled || item.state == .completed {
                                    Button("Retry") { if selectedID == item.id { selectedID = nil }; session.retry(item.id) }
                                }
                                Button { if selectedID == item.id { selectedID = nil }; session.remove(item.id) } label: { Image(systemName: "trash") }.accessibilityLabel("Remove \(item.url.lastPathComponent)")
                            }
                        }
                        if item.state == .running, let progress = item.progress { AnalysisProgressView(progress: progress) }
                        if let analysis = item.result?.analysis {
                            HStack {
                                Text(ByteCountFormatter.string(fromByteCount: analysis.comparison.byteCount, countStyle: .file))
                                ForEach(analysis.definitions.prefix(4), id: \.id) { definition in
                                    if let value = ComparisonTradeoffs.nativeValue(definition.id, in: analysis) { Text("\(definition.name): \(ExportManager.value(value)) \(definition.unit)") }
                                }
                            }.font(.caption).monospacedDigit()
                            Text(tradeoffLabel(item)).font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = item.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                }
                Text("Non-dominated means no compatible completed candidate is both smaller and at least as strong in every available named aggregate. It is a review aid, not a universal winner.").font(.caption).foregroundStyle(.secondary)
                if let id = selectedID, let result = session.items.first(where: { $0.id == id })?.result {
                    Divider()
                    ComparisonResultView(result: result, onInspect: {
                        withAnimation { proxy.scrollTo("viewer-\(result.analysis?.runID.uuidString ?? "legacy")", anchor: .top) }
                    }).id(id)
                }
            }.padding(24)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !session.isBusy else { return false }
            session.add(urls.filter(\.isFileURL)); return !urls.isEmpty
        }
        .onChange(of: selectedID) { _, id in
            if let id { withAnimation { proxy.scrollTo(id, anchor: .top) } }
        }
        }
        .onDisappear { session.cancel() }
    }
    private func tradeoffLabel(_ item: BatchComparison) -> String {
        guard let key = item.compatibilityKey, let analysis = item.result?.analysis else { return "Comparability unavailable" }
        let peers = session.items.filter { $0.id != item.id && $0.state == .completed && $0.compatibilityKey == key }
        guard !peers.isEmpty else { return "No other completed candidate with identical model, preprocessing and coverage yet." }
        if peers.contains(where: { $0.result?.analysis.map { ComparisonTradeoffs.dominates($0, analysis) } ?? false }) {
            return "A compatible candidate is no larger and is at least as strong on every measured aggregate."
        }
        if ComparisonTradeoffs.rankingDefinitions(analysis).contains(where: { ComparisonTradeoffs.nativeValue($0.id, in: analysis)?.doubleValue == nil }) {
            return "Incomplete metric profile; tradeoff ranking unavailable."
        }
        return "Non-dominated among \(peers.count + 1) compatible candidates · inspect the tradeoff."
    }
}
