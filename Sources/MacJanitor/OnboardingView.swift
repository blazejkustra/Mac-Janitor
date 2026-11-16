import AppKit
import Combine
import JanitorCore
import ServiceManagement
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, access, schedule, done

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .access: return "Full Disk Access"
            case .schedule: return "Schedule"
            case .done: return "Ready"
            }
        }

        var symbol: String {
            switch self {
            case .welcome: return "hand.wave"
            case .access: return "lock.shield"
            case .schedule: return "clock"
            case .done: return "flag.checkered"
            }
        }

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
        SidebarWindowLayout {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                SidebarItem(title: step.title, symbol: step.symbol, selected: step == model.step,
                            done: isDone(step)) { model.step = step }
            }
            Spacer()
            AppSignature().padding(.horizontal, 8)
        } page: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
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
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
        .frame(width: 800, height: 600)
        .tint(Palette.accent)
    }

    private func isDone(_ step: OnboardingModel.Step) -> Bool {
        switch step {
        case .access: return store.fullDiskAccess
        case .welcome: return model.step.rawValue > step.rawValue
        default: return false
        }
    }
}

private struct OnboardingButtons: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HStack {
            if model.step != .welcome && model.step != .done {
                Button("Back") { model.back() }
                    .buttonStyle(SoftButtonStyle())
                    .pointingCursor()
            }
            Spacer()
            if model.step == .done {
                Button("Done") { Windows.shared.closeOnboarding() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .pointingCursor()
            } else {
                Button(nextTitle) { model.next() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .pointingCursor()
            }
        }
    }

    private var nextTitle: String {
        switch model.step {
        case .welcome: return "Get started"
        case .access: return store.fullDiskAccess ? "Continue" : "Skip for now"
        default: return "Continue"
        }
    }
}

/// A page heading with a sentence under it.
private struct StepHeading: View {
    let title: String
    let lede: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageTitle(text: title)
            Text(lede)
                .font(.system(size: TextSize.body))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

private struct WelcomeStep: View {
    private let categories = JanitorCore.Category.allCases

    var body: some View {

        StepHeading(title: "Free the space your tools leave behind",
                    lede: "Mac Janitor finds leftovers that can be rebuilt or downloaded again, shows you every one, "
                        + "and removes only what you approve.")
        SectionHeader(title: "What it cleans")
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: categories.count, by: 3)), id: \.self) { start in
                GridRow {
                    ForEach(categories[start..<min(start + 3, categories.count)], id: \.self) { c in
                        HStack(spacing: 8) {
                            Image(systemName: c.symbol).foregroundStyle(Palette.icon).frame(width: 20)
                            Text(c.title).fixedSize()
                        }
                    }
                }
            }
        }
        .font(.system(size: TextSize.body))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()

        SectionHeader(title: "What it never touches")
        Card {
            SettingRow(title: "Anything in use or kept",
                       detail: "Files open in a running app, and anything you pin.",
                       symbol: "hand.raised") { EmptyView() }
            SettingRow(title: "Your work",
                       detail: "Unpushed commits stay. Uncommitted changes are saved to a patch first.",
                       symbol: "arrow.triangle.branch") { EmptyView() }
            SettingRow(title: "Nothing happens on its own",
                       detail: "Automatic cleaning stays off until you turn it on.",
                       symbol: "pause.circle") { EmptyView() }
        }
    }
}

private struct AccessStep: View {
    @EnvironmentObject private var store: Store
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        StepHeading(title: "Let it see the whole disk",
                    lede: "macOS guards Desktop, Documents, Downloads and the Trash. Without Full Disk Access, "
                        + "Mac Janitor skips them and never asks. Only Mac Janitor itself needs to be in the list.")
        Card {
            SettingRow(title: "Full Disk Access",
                       detail: store.fullDiskAccess ? "Granted. Everything can be checked."
                           : "Not granted yet. This updates by itself.",
                       symbol: "lock.shield") {
                StatusPill(text: store.fullDiskAccess ? "Granted" : "Waiting", good: store.fullDiskAccess)
            }
        }
        .padding(.top, 16)
        if !store.fullDiskAccess {
            SectionHeader(title: "How to allow it")
            Card {
                StepRow(n: 1, text: "Open System Settings at Full Disk Access.") {
                    Button("Open System Settings") { SystemSettings.openFullDiskAccess() }
                        .buttonStyle(SoftButtonStyle())
                        .pointingCursor()
                }
                StepRow(n: 2, text: "Turn on Mac Janitor. Not listed? Press + and pick it, or drag it in.") {
                    Button("Show in Finder") { SystemSettings.revealApp() }
                        .buttonStyle(SoftButtonStyle())
                        .pointingCursor()
                }
                StepRow(n: 3, text: "Still waiting? Remove every Mac Janitor from the list with −, "
                            + "add this one with +, then relaunch.") {
                    Button("Relaunch") { Relaunch.now() }
                        .buttonStyle(SoftButtonStyle())
                        .pointingCursor()
                }
            }
        }
        Spacer(minLength: 0)
            .onReceive(poll) { _ in Task { await store.refreshAccess() } }
            .task { await store.refreshAccess() }
    }
}

private struct StepRow<Trailing: View>: View {
    let n: Int
    let text: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text("\(n)")
                .font(.system(size: TextSize.label, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Palette.selection, in: Circle())
            Text(text)
                .font(.system(size: TextSize.body))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ScheduleStep: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: OnboardingModel
    @State private var automatic = false
    @State private var interval = 6.0
    @State private var openAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(title: "Clean on a schedule?",
                        lede: "Scheduled cleans run in the background, even with the menu closed, and follow the "
                            + "same rules as the preview. Large files are never removed automatically.")
            Card {
                SettingRow(title: "Clean automatically", detail: automatic ? "On" : "Off. You clean by hand from the menu bar.") {
                    BigToggle(isOn: $automatic)
                }
                SettingRow(title: "How often", detail: "Cleans run at most this often.") {
                    Picker("How often", selection: $interval) {
                        ForEach(ScheduleChoice.all, id: \.hours) { Text($0.title).tag($0.hours) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .pointingCursor()
                }
                .disabled(!automatic)
                SettingRow(title: "Open at login", detail: "Keep Mac Janitor in the menu bar after a restart.") {
                    BigToggle(isOn: $openAtLogin)
                }
            }
            .padding(.top, 16)
            if LegacyAgent.isInstalled {
                Footnote(text: "An older Mac Janitor background job from the developer install is on this Mac. "
                         + "Turning on automatic cleaning replaces it.")
            }
            Spacer()
            HStack {
                Button("Back") { model.back() }
                    .buttonStyle(SoftButtonStyle())
                    .pointingCursor()
                Spacer()
                Button("Continue") { apply() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .pointingCursor()
            }
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
        StepHeading(title: "You're set",
                    lede: "Mac Janitor lives in the menu bar. Click its icon to see what can go, open a category "
                        + "to check each item, keep what you need, then clean.")
        Card {
            SettingRow(title: "Full Disk Access",
                       detail: store.fullDiskAccess ? "Everything can be checked."
                           : "Desktop, Documents, Downloads and the Trash are skipped.",
                       symbol: "lock.shield") {
                StatusPill(text: store.fullDiskAccess ? "Granted" : "Off", good: store.fullDiskAccess)
            }
            SettingRow(title: "Automatic cleaning", detail: automaticDetail, symbol: "clock") {
                if store.agentStatus == .requiresApproval {
                    Button("Allow") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(SoftButtonStyle())
                        .pointingCursor()
                } else {
                    StatusPill(text: store.automatic ? "On" : "Off", good: store.automatic)
                }
            }
        }
        .padding(.top, 16)
        if let problem = store.problem {
            ProblemBanner(text: problem) { store.problem = nil }.padding(.top, 12)

        }
    }

    private var automaticDetail: String {
        if store.agentStatus == .requiresApproval { return "macOS is waiting for your OK in Login Items." }
        guard store.automatic else { return "You clean by hand from the menu bar." }
        let choice = ScheduleChoice.all.first { $0.hours == store.config.intervalHours }
        return choice?.title ?? "Every \(Format.number(store.config.intervalHours)) hours"
    }
}
