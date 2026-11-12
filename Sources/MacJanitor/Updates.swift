import Foundation
import Sparkle

/// Sparkle's updater, started only inside a bundle whose Info.plist names a feed.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    @Published private(set) var canCheck = false
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                          userDriverDelegate: nil)

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
