import Foundation
import JanitorCLI
import JanitorCore
import ServiceManagement

/// The scheduled job: a LaunchAgent shipped inside the bundle that runs this app's own
/// executable headless, so Full Disk Access granted to the app covers it.
enum Background {
    static var agentPlistName: String { "\(Bundle.main.bundleIdentifier ?? "MacJanitor").agent.plist" }

    static var agent: SMAppService { SMAppService.agent(plistName: agentPlistName) }

    static var status: SMAppService.Status { agent.status }

    static func enable() throws {
        if agent.status != .enabled { try agent.register() }
        LegacyAgent.remove()
    }

    static func disable() throws {
        guard agent.status != .notRegistered && agent.status != .notFound else { return }
        try agent.unregister()
    }
}

extension LegacyAgent {
    /// Off the main thread, so a slow or failing launchctl never holds up launch.
    static func removeInBackground() {
        DispatchQueue.global(qos: .utility).async {
            guard let done = remove() else { return }
            RunLog(dryRun: false, quiet: true).write(done)
        }
    }
}

extension SMAppService.Status {
    var isOn: Bool { self == .enabled || self == .requiresApproval }
}
