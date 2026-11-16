import AppKit

enum Relaunch {
    static func now() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; open \"$1\"",
                            String(getpid()), Bundle.main.bundleURL.path]
        do {
            try reopen.run()
        } catch {
            return
        }
        NSApp.terminate(nil)
    }
}
