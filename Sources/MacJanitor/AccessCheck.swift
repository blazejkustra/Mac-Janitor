import Foundation
import JanitorCore

/// Whether Full Disk Access is granted, asked of a fresh child process: macOS applies a
/// new grant to processes started after it, so the running app may not see it until relaunched.
enum AccessCheck {
    static let argument = "--has-full-disk-access"

    static func run() async -> Bool {
        await Task.detached(priority: .utility) { check() }.value
    }

    private static func check() -> Bool {
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = [argument]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Privacy.hasFullDiskAccess
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
