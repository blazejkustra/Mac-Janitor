import Foundation
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

/// The LaunchAgent the developer install script wrote, which ran `janitor` from the repo folder.
enum LegacyAgent {
    static let label = "com.ignacy.mac-janitor"
    static var plist: URL { Paths.home.appendingPathComponent("Library/LaunchAgents/\(label).plist") }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    static func remove() {
        guard isInstalled else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: plist)
    }
}

extension SMAppService.Status {
    var isOn: Bool { self == .enabled || self == .requiresApproval }
}
