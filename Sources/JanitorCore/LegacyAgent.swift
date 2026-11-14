import Foundation

/// The LaunchAgent the developer install script wrote, which ran `janitor` from the repo folder.
public enum LegacyAgent {
    public static let label = Paths.launchdLabel
    static let launchAgents = Paths.home.appendingPathComponent("Library/LaunchAgents")
    /// `launchctl bootout` statuses for a service that is not loaded.
    static let notLoaded: Set<Int32> = [3, 113]

    public static var isInstalled: Bool { FileManager.default.fileExists(atPath: plist(label, in: launchAgents).path) }

    static func plist(_ label: String, in dir: URL) -> URL { dir.appendingPathComponent("\(label).plist") }

    /// Unloads the agent and deletes its plist. Returns what it did, or nil when it is not installed.
    @discardableResult
    public static func remove() -> String? {
        remove(label: label, in: launchAgents, bootout: launchctlBootout)
    }

    static func remove(label: String, in dir: URL, bootout: (String) -> Int32) -> String? {
        let plist = plist(label, in: dir)
        guard FileManager.default.fileExists(atPath: plist.path) else { return nil }
        let service = "gui/\(getuid())/\(label)"
        let status = bootout(service)
        var done = [status == 0 ? "unloaded \(service)"
                    : notLoaded.contains(status) ? "\(service) was not loaded"
                    : "launchctl bootout \(service) failed with status \(status)"]
        do {
            try FileManager.default.removeItem(at: plist)
            done.append("deleted \(plist.path)")
        } catch {
            done.append("could not delete \(plist.path): \(error.localizedDescription)")
        }
        return "legacy LaunchAgent: " + done.joined(separator: "; ")
    }

    static func launchctlBootout(_ service: String) -> Int32 {
        Shell.run(["/bin/launchctl", "bootout", service], timeout: 30).status
    }
}
