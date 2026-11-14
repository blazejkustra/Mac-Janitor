import Foundation
import JanitorCore

/// Runs this app's own executable headless (`MacJanitor run ...`) and decodes the Report it prints.
enum JanitorRunner {
    struct Outcome {
        var report: Report?
        /// What to show the user when the run did not cleanly produce a report.
        var problem: String?
        /// Another run, usually the scheduled one, held the lock.
        var locked = false
    }

    static var executable: URL { Bundle.main.executableURL! }

    /// With `only`, a real run acts on just those action ids, recording the sizes given
    /// for them. `onEvent` gets the run's progress, on a background thread.
    static func run(dryRun: Bool, only: [(id: String, bytes: Int64)]? = nil,
                    onEvent: @escaping @Sendable (ScanEvent) -> Void = { _ in }) async -> Outcome {
        await Task.detached(priority: .userInitiated) { runBlocking(dryRun: dryRun, only: only, onEvent: onEvent) }.value
    }

    private static func runBlocking(dryRun: Bool, only: [(id: String, bytes: Int64)]?, onEvent: @escaping (ScanEvent) -> Void) -> Outcome {
        let exe = executable
        var arguments = ["run", "--json", "--progress"] + (dryRun ? ["--dry-run"] : [])
        var onlyFile: URL?
        defer { onlyFile.map { try? FileManager.default.removeItem(at: $0) } }
        if let only {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("janitor-only-\(UUID().uuidString).txt")
            do {
                try only.map { "\($0.id)\t\($0.bytes)" }.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            } catch {
                return Outcome(problem: "Could not write \(file.path): \(error.localizedDescription)")
            }
            onlyFile = file
            arguments += ["--only", file.path]
        }
        return launch(exe, arguments, onEvent: onEvent)
    }

    private static func launch(_ exe: URL, _ arguments: [String], onEvent: @escaping (ScanEvent) -> Void) -> Outcome {
        let process = Process()
        process.executableURL = exe
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Outcome(problem: "Could not start janitor: \(error.localizedDescription)")
        }

        // Drain both pipes at once so a full one cannot stall the child.
        var errData = Data()
        let stderrDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errData = readEvents(from: err.fileHandleForReading, onEvent: onEvent)
            stderrDone.signal()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        stderrDone.wait()
        process.waitUntilExit()

        let report = try? JSONDecoder.janitor.decode(Report.self, from: outData)
        let stderr = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let status = process.terminationStatus

        if process.terminationReason == .uncaughtSignal {
            return Outcome(report: report, problem: "janitor was killed by signal \(status)")
        }
        if status != 0 && stderr.hasSuffix("another janitor run is in progress") {
            return Outcome(locked: true)
        }
        if status != 0 {
            // The CLI exits 1 when an action failed; those items already show in red.
            if !stderr.isEmpty { return Outcome(report: report, problem: stderr) }
            return Outcome(report: report, problem: report == nil ? "janitor exited with status \(status)" : nil)
        }
        if report == nil {
            return Outcome(problem: "janitor printed no readable report" + (stderr.isEmpty ? "" : ": " + stderr))
        }
        return Outcome(report: report)
    }

    /// Hands progress lines to `onEvent` as they arrive and returns everything else.
    private static func readEvents(from handle: FileHandle, onEvent: (ScanEvent) -> Void) -> Data {
        var pending = Data()
        var other = Data()
        func consume(_ line: Data) {
            if let event = ScanEvent.parse(Substring(decoding: line, as: UTF8.self)) {
                onEvent(event)
            } else {
                other.append(line)
                other.append(0x0A)
            }
        }
        var chunk = handle.availableData
        while !chunk.isEmpty {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                consume(pending[pending.startIndex..<newline])
                pending.removeSubrange(pending.startIndex...newline)
            }
            chunk = handle.availableData
        }
        if !pending.isEmpty { consume(pending) }
        return other
    }
}
