import SwiftUI
import AVFoundation
import AppKit

struct PlaybackComparisonView: View {
    @ObservedObject var controller: PlaybackController
    let result: VMAFCalculator.VMAFResult
    @State private var wipe = false
    @State private var wipePosition = 0.5
    @State private var actualSize = false
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("View", selection: $wipe) { Text("Side by side").tag(false); Text("Wipe").tag(true) }.pickerStyle(.segmented).frame(width: 220)
                Toggle("1:1 pixels", isOn: $actualSize).toggleStyle(.button)
                Slider(value: $zoom, in: 1...8).frame(width: 100).accessibilityLabel("Shared zoom")
                Text(String(format: "%.1f×", zoom)).monospacedDigit()
                Button("Reset view") { zoom = 1; pan = .zero; actualSize = false }
            }
            GeometryReader { geometry in
                let width = wipe ? geometry.size.width : (geometry.size.width - 8) / 2
                let canvas = CGSize(width: width, height: geometry.size.height)
                Group {
                    if wipe {
                        ZStack(alignment: .leading) {
                            video(controller.referencePlayer, label: "Source", canvas: canvas)
                            video(controller.comparisonPlayer, label: "Encode", canvas: canvas)
                                .mask(alignment: .leading) { Rectangle().frame(width: width * wipePosition) }
                            Rectangle().fill(.white).frame(width: 2).offset(x: width * wipePosition)
                            VStack {
                                HStack {
                                    Text("Encode"); Spacer(); Text("Source")
                                }.font(.caption.bold()).padding(6).background(.black.opacity(0.75)).padding(8)
                                Spacer()
                            }.allowsHitTesting(false)
                        }
                    } else {
                        HStack(spacing: 8) {
                            video(controller.referencePlayer, label: "Source", canvas: canvas)
                            video(controller.comparisonPlayer, label: "Encode", canvas: canvas)
                        }
                    }
                }
                .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in pan.width += value.translation.width; pan.height += value.translation.height })
            }.frame(height: 320).background(.black).clipShape(RoundedRectangle(cornerRadius: 8))
            if wipe { Slider(value: $wipePosition, in: 0...1).accessibilityLabel("Wipe boundary: encode on left, source on right") }
            if let error = controller.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if !controller.ready && controller.error == nil { HStack { ProgressView().controlSize(.small); Text("Verifying files and preparing native playback…") } }
            HStack {
                Button { controller.step(-1) } label: { Image(systemName: "backward.frame") }.help("Previous matched frame (Left arrow)").keyboardShortcut(.leftArrow, modifiers: []).accessibilityLabel("Previous matched frame")
                Button { controller.toggle() } label: { Image(systemName: controller.playing ? "pause.fill" : "play.fill") }.keyboardShortcut(.space, modifiers: []).accessibilityLabel(controller.playing ? "Pause pair" : "Play pair")
                Button { controller.step(1) } label: { Image(systemName: "forward.frame") }.help("Next matched frame (Right arrow)").keyboardShortcut(.rightArrow, modifiers: []).accessibilityLabel("Next matched frame")
                Toggle("Loop selection", isOn: $controller.loop).toggleStyle(.button)
                Text(String(format: "%.6f s · frame %d", controller.timestamp, controller.selectedIndex)).monospacedDigit().font(.caption)
                if controller.seeking { ProgressView().controlSize(.mini) }
            }.disabled(!controller.ready)
            Slider(value: Binding(get: { controller.timestamp }, set: { controller.seek(time: $0) }), in: 0...max(controller.duration, 0.001))
                .disabled(!controller.ready).accessibilityLabel("Matched comparison timeline")
            Text("Native macOS SDR preview · muted · shared transport and frame mapping. Display color rendering is managed by AVFoundation; it is separate from the recorded metric conversion.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func video(_ player: AVPlayer, label: String, canvas: CGSize) -> some View {
        let stream = result.analysis?.referenceStream
        let pixels = CGSize(width: stream?.width ?? 1920, height: stream?.height ?? 1080)
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let scale = actualSize ? 1 / backing : min(canvas.width / pixels.width, canvas.height / pixels.height)
        return ZStack(alignment: .topLeading) {
            Color.black
            NativePlayerSurface(player: player)
                .frame(width: pixels.width * scale * zoom, height: pixels.height * scale * zoom)
                .position(x: canvas.width / 2 + pan.width + drag.width, y: canvas.height / 2 + pan.height + drag.height)
            if !wipe { Text(label).font(.caption.bold()).padding(6).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4)).padding(8) }
        }.frame(width: canvas.width, height: canvas.height).clipped().accessibilityLabel("\(label) video")
    }
}

private struct NativePlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerLayerView { let view = PlayerLayerView(); view.playerLayer.player = player; return view }
    func updateNSView(_ view: PlayerLayerView, context: Context) { view.playerLayer.player = player }
    static func dismantleNSView(_ view: PlayerLayerView, coordinator: ()) { view.playerLayer.player = nil }
}
private final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer = playerLayer; playerLayer.videoGravity = .resizeAspect }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
