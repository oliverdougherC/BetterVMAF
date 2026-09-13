import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    var body: some View {
        TabView {
            VMAFView().tabItem { Label("Compare", systemImage: "rectangle.split.2x1") }
            VMAFBatchView().tabItem { Label("Batch", systemImage: "tray.full") }
        }
        .frame(minWidth: 760, minHeight: 600)
    }
}

struct VMAFView: View {
    @StateObject private var session = ComparisonSession()
    @State private var setupExpanded = true
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Compare your encode").font(.largeTitle.bold())
                Text("Choose the original source and an encode, then inspect what changed.")
                    .foregroundStyle(.secondary)
                ReviewDisclosure("Source, encode and viewing profile", isExpanded: $setupExpanded) {
                HStack(alignment: .top) {
                    VideoInputCard(title: "Source · original", url: session.source, disabled: session.isBusy) {
                        session.select($0, source: true)
                    }
                    VideoInputCard(title: "Encode · comparison", url: session.encode, disabled: session.isBusy) {
                        session.select($0, source: false)
                    }
                }
                ReviewDisclosure("Viewing assumptions") {
                    Picker("Viewing profile", selection: Binding(get: { session.configuration.viewingProfile }, set: { session.selectProfile($0) })) {
                        ForEach(AnalysisConfiguration.ViewingProfile.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.disabled(session.isBusy).accessibilityIdentifier("viewingProfilePicker")
                    Text("SDR, equal canvas, strict matched timestamps. The profile describes the model's viewing assumptions.").font(.caption).foregroundStyle(.secondary)
                }
                }
                HStack {
                    Button("Analyze", systemImage: "waveform.path.ecg", action: session.start)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("analyzeComparison")
                        .disabled(session.isBusy || session.source == nil || session.encode == nil)
                    if session.isBusy {
                        ProgressView().controlSize(.small)
                        Text(session.state == .cancelling ? "Stopping analysis…" : "Analyzing every matched frame…")
                            .foregroundStyle(.secondary)
                        Button("Cancel", action: session.cancel).disabled(session.state == .cancelling)
                    }
                }
                if let progress = session.progress, session.isBusy { AnalysisProgressView(progress: progress) }
                if let error = session.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("analysisError")
                }
                if let result = session.result {
                    ComparisonResultView(result: result, onInspect: {
                        withAnimation { proxy.scrollTo("viewer-\(result.analysis?.runID.uuidString ?? "legacy")", anchor: .top) }
                    }).id("comparisonResult")
                }
            }.padding(24)
        }
        .onChange(of: session.result?.analysis?.runID) { _, id in
            guard id != nil else { setupExpanded = true; return }
            setupExpanded = false
            Task { @MainActor in
                await Task.yield()
                withAnimation { proxy.scrollTo("comparisonResult", anchor: .top) }
            }
        }
        }
        .onDisappear { session.cancel() }
    }
}

struct VideoInputCard: View {
    let title: String
    let url: URL?
    let disabled: Bool
    let select: (URL) -> Void
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(url?.lastPathComponent ?? "Drop a video here")
                .lineLimit(2).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                .help(url?.path ?? "Choose a local video")
            Button(url == nil ? "Choose video…" : "Change video…") {
                VideoSelection.choose { if let first = $0.first { select(first) } }
            }.disabled(disabled)
                .accessibilityIdentifier("choose-\(title)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(targeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: URL.self) { urls, _ in
            guard !disabled, let url = urls.first, url.isFileURL else { return false }
            select(url); return true
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

@MainActor
enum VideoSelection {
    private static var choosing = false
    static func choose(multiple: Bool = false, completion: @escaping ([URL]) -> Void) {
        guard !choosing else { return }
        choosing = true
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .data]
        panel.begin { response in
            choosing = false
            if response == .OK { completion(panel.urls) }
        }
    }
}

struct ResultRow: View {
    let title: String
    let value: String
    init(title: String, value: String) { self.title = title; self.value = value }
    init(title: String, value: Double) { self.init(title: title, value: String(format: "%.2f", value)) }
    var body: some View { HStack { Text(title); Spacer(); Text(value).monospacedDigit() } }
}

struct AnalysisProgressView: View {
    let progress: AnalysisProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress.fraction)
            Text("Frame \(progress.frameCount)" + (progress.totalFrames.map { " of \($0)" } ?? "") + String(format: " · %.1f processing fps", progress.processingFPS))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
