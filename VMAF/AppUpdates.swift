import Sparkle
import SwiftUI

@MainActor
final class ComparisonActivity: ObservableObject {
    static let shared = ComparisonActivity()

    @Published private(set) var isActive = false
    private var comparisons = Set<UUID>()

    func begin() -> UUID {
        let id = UUID()
        comparisons.insert(id)
        isActive = true
        return id
    }

    func end(_ id: UUID) {
        comparisons.remove(id)
        isActive = !comparisons.isEmpty
    }
}

@MainActor
final class AppUpdates: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = controller
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if ComparisonActivity.shared.isActive {
            throw NSError(domain: "BetterVMAF.Update", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Check for updates after the video comparisons finish."
            ])
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Sparkle sends a normal quit event, including for updates downloaded on
        // an earlier launch. Its installer can retry once comparisons finish.
        ComparisonActivity.shared.isActive ? .terminateCancel : .terminateNow
    }
}

struct CheckForUpdates: View {
    let updater: SPUUpdater
    @ObservedObject private var activity = ComparisonActivity.shared
    @State private var canCheck = false

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!canCheck || activity.isActive)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
