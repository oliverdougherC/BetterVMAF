import Sparkle
import SwiftUI

@MainActor
final class ComparisonActivity: ObservableObject {
    static let shared = ComparisonActivity()

    @Published var isRestarting = false
    @Published private(set) var isQuitting = false
    @Published private var comparisons = [UUID: ComparisonRun]()

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
final class AppUpdates: NSObject, ObservableObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private let activity: ComparisonActivity
    private var confirmingQuit = false
    @Published private(set) var deferredInstallation: (() -> Void)?
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

    func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock install: @escaping () -> Void
    ) -> Bool {
        guard postponeInstallationIfNeeded(install) else { return false }

        // Sparkle's Ready to Install button has already used its reply. Close
        // that window and let our menu resume this same installation.
        controller?.userDriver.dismissUpdateInstallation()
        Task { @MainActor in
            guard deferredInstallation != nil, !confirmingQuit, !activity.isQuitting else { return }
            let alert = NSAlert()
            alert.messageText = "Comparison in progress"
            alert.informativeText = "Choose Install Downloaded Update from the Better VMAF menu when you’re ready to close your comparison results."
            alert.runModal()
        }
        return true
    }

    func postponeInstallationIfNeeded(_ install: @escaping () -> Void) -> Bool {
        guard activity.isActive || confirmingQuit || activity.isQuitting else { return false }
        deferredInstallation = install
        return true
    }

    func installDownloadedUpdate() {
        guard !activity.isActive, activity.canStart, !confirmingQuit,
              let install = deferredInstallation else { return }
        deferredInstallation = nil
        install()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        // Sparkle calls this before requesting termination. Keep new work
        // blocked through the quit event and any Sparkle termination retries.
        activity.isRestarting = true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        deferredInstallation = nil
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
        guard activity.isActive else {
            _ = activity.stopForQuit()
            return .terminateNow
        }
        guard !activity.isRestarting else { return .terminateCancel }

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
    @ObservedObject var updates: AppUpdates
    @ObservedObject private var activity = ComparisonActivity.shared
    let updater: SPUUpdater
    @State private var canCheck = false

    var body: some View {
        Group {
            if updates.deferredInstallation != nil {
                Button("Install Downloaded Update", action: updates.installDownloadedUpdate)
                    .disabled(activity.isActive || !activity.canStart)
            } else {
                Button("Check for Updates…", action: updater.checkForUpdates)
                    .disabled(!canCheck)
            }
        }
        .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
