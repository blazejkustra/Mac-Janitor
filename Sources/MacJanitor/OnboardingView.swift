import AppKit
import Combine
import JanitorCore
import ServiceManagement
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, access, schedule, done
    }

    @Published var step: Step = .welcome

    func next() {
        step = Step(rawValue: step.rawValue + 1) ?? .done
    }

    func back() {
        step = Step(rawValue: step.rawValue - 1) ?? .welcome
    }
}

enum SystemSettings {
    static let fullDiskAccess = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func openFullDiskAccess() {
        NSWorkspace.shared.open(fullDiskAccess)
    }

    static func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepIndicator(step: model.step)
                .padding(.bottom, 20)
            Group {
                switch model.step {
                case .welcome: WelcomeStep()
                case .access: AccessStep()
                case .schedule: ScheduleStep(model: model)
                case .done: DoneStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if model.step != .schedule {
                OnboardingButtons(model: model)
            }
        }
        .padding(28)
        .frame(width: 560, height: 520)
    }
}

private struct StepIndicator: View {
    let step: OnboardingModel.Step

    private let names = ["Welcome", "Permissions", "Schedule", "Done"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { s in
                HStack(spacing: 6) {
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(names[s.rawValue])
                        .font(.caption)
                        .foregroundStyle(s == step ? .primary : .secondary)
                }
                if s != .done {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 24, height: 1)
                }
            }
        }
    }
}

private struct OnboardingButtons: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: OnboardingModel

    private var nextTitle: String {
        switch model.step {
        case .welcome: return "Get started"
        case .access: return store.fullDiskAccess ? "Continue" : "Skip for now"
        default: return "Continue"
        }
    }

    var body: some View {
        HStack {
            if model.step != .welcome && model.step != .done {
                Button("Back") { model.back() }
                    .pointingCursor()
            }
            Spacer()
            if model.step == .done {
                Button("Done") { Windows.shared.closeOnboarding() }
                    .keyboardShortcut(.defaultAction)
                    .pointingCursor()
            } else {
                Button(nextTitle) { model.next() }
                    .keyboardShortcut(.defaultAction)
                    .pointingCursor()
            }
        }
        .controlSize(.large)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mac Janitor frees disk space that developer tools leave behind")
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("It looks for leftovers that can be rebuilt or downloaded again, shows you everything it found, "
                 + "and removes only what you approve. You can also let it clean on a schedule.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Bullet(symbol: "shippingbox", title: "What it cleans",
                       text: "Old git worktrees, node_modules and build folders in idle projects, unused caches, "
                           + "Docker images, Android emulators and old items in the Trash.")
                Bullet(symbol: "hand.raised", title: "What it never touches",
                       text: "Anything open in a running app, anything you pin to keep, unpushed commits and "
                           + "uncommitted changes (saved to a patch first), and your documents, photos and music.")
                Bullet(symbol: "eye", title: "Nothing happens on its own yet",
                       text: "Automatic cleaning stays off until you turn it on in the next steps.")
            }
            .padding(.top, 6)
        }
    }
}

private struct Bullet: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AccessStep: View {
    @EnvironmentObject private var store: Store
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Give Mac Janitor Full Disk Access")
                .font(.title2.weight(.semibold))
            Text("macOS protects your Desktop, Documents, Downloads and the Trash. Without access, Mac Janitor "
                 + "skips them and never asks. Only Mac Janitor itself needs to be in the list.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PermissionRow(title: "Full Disk Access",
                          detail: store.fullDiskAccess ? "Granted. Everything can be checked."
                              : "Not granted yet. This page updates by itself.",
                          granted: store.fullDiskAccess)
            if !store.fullDiskAccess {
                VStack(alignment: .leading, spacing: 8) {
                    NumberedStep(n: 1, text: "Click Open System Settings.")
                    NumberedStep(n: 2, text: "Turn on the switch next to Mac Janitor. If it is not in the list, "
                        + "click + and choose Mac Janitor, or drag it in from the Finder window.")
                    NumberedStep(n: 3, text: "If macOS offers to quit and reopen Mac Janitor, choose Later. "
                        + "The new access applies to every scan from now on.")
                }
                HStack {
                    Button("Open System Settings") { SystemSettings.openFullDiskAccess() }
                        .buttonStyle(.borderedProminent)
                        .pointingCursor()
                    Button("Show Mac Janitor in Finder") { SystemSettings.revealApp() }
                        .pointingCursor()
                }
                Text("You can skip this and turn it on later from Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(poll) { _ in Task { await store.refreshAccess() } }
        .task { await store.refreshAccess() }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NumberedStep: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScheduleStep: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: OnboardingModel
    @State private var automatic = false
    @State private var interval = 6.0
    @State private var openAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clean automatically?")
                .font(.title2.weight(.semibold))
            Text("Scheduled cleans run in the background, even with the menu closed, and follow the same rules "
                 + "as the preview. Large files are never removed automatically.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                Toggle("Clean automatically", isOn: $automatic)
                Picker("How often", selection: $interval) {
                    ForEach(ScheduleChoice.all, id: \.hours) { Text($0.title).tag($0.hours) }
                }
                .disabled(!automatic)
                Toggle("Open Mac Janitor at login", isOn: $openAtLogin)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 170)
            if LegacyAgent.isInstalled {
                Label("An older Mac Janitor background job from the developer install is on this Mac. "
                      + "Turning on automatic cleaning replaces it.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack {
                Button("Back") { model.back() }
                    .pointingCursor()
                Spacer()
                Button("Continue") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .pointingCursor()
            }
            .controlSize(.large)
        }
        .onAppear {
            automatic = store.automatic
            interval = ScheduleChoice.nearest(store.config.intervalHours)
            openAtLogin = store.loginStatus.isOn || !Windows.setupDone
        }
    }

    private func apply() {
        store.update { $0.intervalHours = interval }
        store.setAutomatic(automatic)
        if openAtLogin != store.loginStatus.isOn { store.setLaunchAtLogin(openAtLogin) }
        model.next()
    }
}

/// The schedule as people say it.
struct ScheduleChoice {
    let hours: Double
    let title: String

    static let all = [
        ScheduleChoice(hours: 3, title: "Every 3 hours"),
        ScheduleChoice(hours: 6, title: "Every 6 hours"),
        ScheduleChoice(hours: 12, title: "Twice a day"),
        ScheduleChoice(hours: 24, title: "Once a day"),
        ScheduleChoice(hours: 168, title: "Once a week"),
    ]

    static func nearest(_ hours: Double) -> Double {
        all.min { abs($0.hours - hours) < abs($1.hours - hours) }!.hours
    }
}

private struct DoneStep: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're set")
                .font(.title2.weight(.semibold))
            Text("Mac Janitor lives in the menu bar. Click its icon to see what can be cleaned, look inside each "
                 + "category, keep anything you need, and clean when you're ready.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PermissionRow(title: "Full Disk Access",
                          detail: store.fullDiskAccess ? "Granted" : "Off: Desktop, Documents, Downloads and the Trash are skipped",
                          granted: store.fullDiskAccess)
            PermissionRow(title: "Automatic cleaning", detail: automaticDetail, granted: store.automatic)
            if store.agentStatus == .requiresApproval {
                HStack {
                    Text("macOS needs your OK to run Mac Janitor in the background.")
                        .font(.callout)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .pointingCursor()
                }
            }
            if let problem = store.problem {
                Text(ProblemBanner.shorten(problem)).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var automaticDetail: String {
        if store.agentStatus == .requiresApproval { return "Waiting for your approval in Login Items" }
        guard store.automatic else { return "Off. You clean by hand from the menu bar." }
        let choice = ScheduleChoice.all.first { $0.hours == store.config.intervalHours }
        return "On, \(choice?.title.lowercased() ?? "every \(Format.number(store.config.intervalHours)) hours")"
    }
}
