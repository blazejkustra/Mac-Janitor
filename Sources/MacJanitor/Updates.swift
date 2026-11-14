import Foundation
import Sparkle

/// Sparkle's updater, started only inside a bundle whose Info.plist names a feed.
@MainActor
final class Updates: NSObject, ObservableObject {
    static let shared = Updates()

    @Published private(set) var canCheck = false
    let reminder = UpdateReminder()
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                               userDriverDelegate: self)

    private var updater: SPUUpdater { controller.updater }

    private static var hasFeed: Bool {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    }

    func start() {
        guard Self.hasFeed else { return }
        controller.startUpdater()
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    var checksAutomatically: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    func check() {
        controller.checkForUpdates(nil)
    }
}

/// A scheduled check found an update that Sparkle left for us to point out:
/// a dot on the menu-bar icon and a row in the panel, until the user looks at it.
@MainActor
final class UpdateReminder: ObservableObject {
    @Published var version: String?

    init(version: String? = nil) {
        self.version = version
    }
}

/// Gentle reminders: an accessory app's update alert can open behind other windows
/// and go unnoticed, so outside immediate focus Sparkle waits for the reminder instead.
extension Updates: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                          andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { reminder.version = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { reminder.version = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { reminder.version = nil }
    }
}
