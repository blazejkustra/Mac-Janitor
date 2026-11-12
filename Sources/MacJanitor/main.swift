import Foundation
import JanitorCLI
import JanitorCore

let args = Array(CommandLine.arguments.dropFirst())
if CLI.handles(args) {
    exit(CLI.main(args))
}
if args.first == AccessCheck.argument {
    exit(Privacy.hasFullDiskAccess ? 0 : 1)
}
// `MacJanitor --snapshot <dir>` renders fixture states to PNGs and exits.
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    MainActor.assumeIsolated { Snapshot.render(to: URL(fileURLWithPath: args[i + 1])) }
    exit(0)
}
MacJanitorApp.main()
