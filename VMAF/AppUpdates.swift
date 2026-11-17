import Sparkle
import SwiftUI

@MainActor
final class ComparisonActivity: ObservableObject {
    static let shared = ComparisonActivity()

    @Published var isRestarting = false
    @Published private(set) var isQuitting = false
    private var comparisons = [UUID: ComparisonRun]()

    var isActive: Bool { !comparisons.isEmpty }
    var canStart: Bool { !isRestarting && !isQuitting }

    func begin() -> ComparisonRun? {
        guard canStart else { return nil }
        let run = ComparisonRun()
        comparisons[run.id] = run
        return run
    }

    func end(_ run: ComparisonRun) {
        comparisons.removeValue(forKey: run.id)
    }

    func stopForQuit() -> [ComparisonRun] {
        isQuitting = true
        let runs = Array(comparisons.values)
        for run in runs { run.cancel() }
        return runs
    }
}

@MainActor
final class AppUpdates: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private let activity: ComparisonActivity
    private var confirmingQuit = false
    private(set) lazy var controller: SPUStandardUpdaterController? = {
        let info = Bundle.main.infoDictionary
        guard let feed = info?["SUFeedURL"] as? String,
              let url = URL(string: feed), url.host != nil,
              let key = info?["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32 else { return nil }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
        )
        controller.startUpdater()
        controller.updater.clearFeedURLFromUserDefaults()
        return controller
    }()

    override convenience init() {
        self.init(activity: .shared)
    }

    init(activity: ComparisonActivity) {
        self.activity = activity
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = controller
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        allowUpdateRelaunch {
            let alert = NSAlert()
            alert.messageText = "Comparison in progress"
            alert.informativeText = "Check for updates again when you’re ready to close your comparison results."
            alert.runModal()
        }
    }

    func allowUpdateRelaunch(onBusy: @escaping @MainActor () -> Void) -> Bool {
        guard !activity.isQuitting else { return false }
        guard activity.isActive else { return true }

        // Sparkle aborts the relaunch attempt. Deferring it until the last
        // worker finishes could close the app before the user sees the result.
        Task { @MainActor in
            if !activity.isQuitting { onBusy() }
        }
        return false
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // Close the gap between Sparkle's relaunch decision and its quit event.
        activity.isRestarting = true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        // Sparkle may recover from a failed or cancelled restart in this process.
        activity.isRestarting = false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestTermination(confirm: {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Quit and stop comparisons?"
            alert.informativeText = "In-progress comparisons will stop. Unexported results will be lost."
            alert.addButton(withTitle: "Keep Comparing").keyEquivalent = "\r"
            alert.addButton(withTitle: "Quit").keyEquivalent = ""
            return alert.runModal() == .alertSecondButtonReturn
        }, reply: { sender.reply(toApplicationShouldTerminate: $0) })
    }

    func requestTermination(
        confirm: () -> Bool, reply: @escaping @MainActor (Bool) -> Void
    ) -> NSApplication.TerminateReply {
        guard !confirmingQuit, !activity.isQuitting else { return .terminateCancel }
        guard activity.isActive else { return .terminateNow }

        confirmingQuit = true
        let shouldQuit = confirm()
        confirmingQuit = false
        guard shouldQuit else { return .terminateCancel }

        let runs = activity.stopForQuit()
        Task {
            for run in runs { await run.waitForExit() }
            reply(true)
        }
        return .terminateLater
    }
}

struct CheckForUpdates: View {
    let updater: SPUUpdater
    @State private var canCheck = false

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
