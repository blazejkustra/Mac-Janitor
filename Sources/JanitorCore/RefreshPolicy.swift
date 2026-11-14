import Foundation

/// When the app scans again, and whether the scan shows its progress.
public enum RefreshPolicy {
    public enum Trigger {
        case panelOpened
        case timer
        /// The app changed something itself: a clean, a pin, a settings change.
        case changed
        /// Option-opening the panel or the refresh button.
        case forced
    }

    public enum Decision: Equatable {
        case none
        /// Keep showing the last result until the new one is done.
        case quiet
        /// Show progress: there is no result to show meanwhile, or the user asked.
        case visible
    }

    public struct Power: Equatable {
        public var onBattery: Bool
        public var lowPowerMode: Bool

        public init(onBattery: Bool, lowPowerMode: Bool) {
            self.onBattery = onBattery
            self.lowPowerMode = lowPowerMode
        }

        var saving: Bool { onBattery || lowPowerMode }
    }

    /// `resultAge` is nil without a result; `outdated` means the settings or a real run
    /// changed what the result would hold. Callers skip it while another run holds the lock.
    public static func decide(_ trigger: Trigger, resultAge: TimeInterval?, interval: TimeInterval,
                              outdated: Bool, power: Power) -> Decision {
        let quietFallback: Decision = resultAge == nil ? .visible : .quiet
        switch trigger {
        case .forced:
            return .visible
        case .changed:
            return quietFallback
        case .panelOpened:
            return isDue(resultAge, interval, outdated) ? quietFallback : .none
        case .timer:
            return isDue(resultAge, interval, outdated) && !power.saving ? quietFallback : .none
        }
    }

    private static func isDue(_ age: TimeInterval?, _ interval: TimeInterval, _ outdated: Bool) -> Bool {
        guard let age else { return true }
        return outdated || age >= interval
    }
}
