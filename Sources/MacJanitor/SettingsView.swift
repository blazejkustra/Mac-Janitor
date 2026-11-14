import AppKit
import JanitorCore
import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable {
    case general, schedule, categories, kept, permissions, about

    var title: String {
        switch self {
        case .general: return "General"
        case .schedule: return "Automatic cleaning"
        case .categories: return "What to clean"
        case .kept: return "Kept items"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .schedule: return "clock"
        case .categories: return "checklist"
        case .kept: return "pin"
        case .permissions: return "lock.shield"
        case .about: return "info"
        }
    }

}

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State var page: SettingsPage = .general

    var body: some View {
        SidebarWindowLayout {
            ForEach(SettingsPage.allCases, id: \.self) { p in
                SidebarItem(title: p.title, symbol: p.symbol, selected: p == page) { page = p }
            }
            Spacer()
            AppSignature().padding(.horizontal, 8)
        } page: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageTitle(text: page.title)
                    if let problem = store.problem {
                        ProblemBanner(text: problem) { store.problem = nil }.padding(.top, 12)
                    }
                    content
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 760, height: 560)
        .tint(Palette.accent)
        .task { await store.refreshAccess() }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .general: GeneralPage()
        case .schedule: SchedulePage()
        case .categories: CategoriesPage()
        case .kept: KeptPage()
        case .permissions: PermissionsPage()
        case .about: AboutPage()
        }
    }
}

// MARK: - Pages

private struct GeneralPage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        SectionHeader(title: "Startup")
        Card {
            SettingRow(title: "Open at login", detail: "Keep Mac Janitor in the menu bar after a restart.") {
                BigToggle(isOn: Binding(get: { store.loginStatus.isOn }, set: { store.setLaunchAtLogin($0) }))
            }
        }
        SectionHeader(title: "Scanning")
        Card {
            SettingRow(title: "Scan again after", detail: "Older results are refreshed in the background, except on battery.") {
                Picker("Scan again after", selection: store.binding(\.refreshMinutes)) {
                    ForEach(RefreshChoice.all, id: \.minutes) { Text($0.title).tag($0.minutes) }
                    if !RefreshChoice.all.contains(where: { $0.minutes == store.config.refreshMinutes }) {
                        Text("\(Format.number(store.config.refreshMinutes)) min").tag(store.config.refreshMinutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .pointingCursor()
            }
        }
        SectionHeader(title: "Help")
        Card {
            SettingRow(title: "Setup guide", detail: "Walk through permissions and the schedule again.") {
                Button("Open") { Windows.shared.showOnboarding() }.buttonStyle(SoftButtonStyle()).pointingCursor()
            }
            SettingRow(title: "Activity log", detail: "Every item a clean removed, with the reason.") {
                Button("Show") { store.openLog() }.buttonStyle(SoftButtonStyle()).pointingCursor()
            }
            SettingRow(title: "Quit Mac Janitor", detail: "Scheduled cleans keep running while it is closed.") {
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(SoftButtonStyle()).pointingCursor()
            }
        }
    }
}

private struct SchedulePage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        SectionHeader(title: "Schedule")
        Card {
            SettingRow(title: "Clean automatically",
                       detail: store.automatic ? "Runs in the background, even with the menu closed."
                           : "Off. Nothing is removed unless you click Clean.") {
                BigToggle(isOn: Binding(get: { store.automatic }, set: { store.setAutomatic($0) }))
            }
            SettingRow(title: "How often", detail: "Cleans run at most this often.") {
                Picker("How often", selection: store.binding(\.intervalHours)) {
                    ForEach(ScheduleChoice.all, id: \.hours) { Text($0.title).tag($0.hours) }
                    if !ScheduleChoice.all.contains(where: { $0.hours == store.config.intervalHours }) {
                        Text("Every \(Format.number(store.config.intervalHours)) hours").tag(store.config.intervalHours)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .pointingCursor()
            }
            .disabled(!store.automatic)
            SettingRow(title: "Clean early when space is low",
                       detail: "Below this much free space, a clean starts without waiting.") {
                ValueStepper(value: store.binding(\.lowDiskGB), range: 5...200, step: 5, unit: "GB")
            }
            .disabled(!store.automatic)
        }
        if store.agentStatus == .requiresApproval {
            SectionHeader(title: "Needs your OK")
            Card {
                SettingRow(title: "Allow in the background",
                           detail: "macOS asks before an app runs on a schedule. Allow Mac Janitor in Login Items.") {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(SoftButtonStyle()).pointingCursor()
                }
            }
        }
        Footnote(text: "Large forgotten files are never removed automatically, only when you clean by hand.")
    }
}

private struct CategoriesPage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        SectionHeader(title: "Categories", action: ("Reset to defaults", resetThresholds))
        ForEach(JanitorCore.Category.allCases, id: \.self) { category in
            CategoryCard(category: category).padding(.bottom, 12)
        }
        Footnote(text: "Turned-off categories are not checked or cleaned. A manual clean always shows everything first.")
    }

    private func resetThresholds() {
        store.update { cfg in
            let defaults = Config()
            for t in JanitorCore.Category.allCases.flatMap(Threshold.all) { cfg[keyPath: t.key] = defaults[keyPath: t.key] }
        }
    }
}

private struct CategoryCard: View {
    @EnvironmentObject private var store: Store
    let category: JanitorCore.Category

    var body: some View {
        let enabled = store.config.enabled(category)
        Card {
            SettingRow(title: category.title, detail: category.explanation(store.config),
                       symbol: category.symbol) {
                BigToggle(isOn: Binding(get: { enabled }, set: { store.setEnabled(category, $0) }))
            }
            if enabled {
                ForEach(Threshold.all(for: category), id: \.title) { t in
                    SettingRow(title: t.title) {
                        ValueStepper(value: store.binding(t.key), range: t.range, step: t.step, unit: t.unit)
                    }
                    .padding(.leading, 40)
                }
            }
        }
    }
}

private struct KeptPage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        SectionHeader(title: "Never removed",
                      action: store.config.keep.isEmpty ? nil : ("Clear all", { store.update { $0.keep = [] } }))
        Card {
            ForEach(store.config.keep, id: \.self) { KeptRow(target: $0) }
            SettingRow(title: store.config.keep.isEmpty ? "Nothing kept yet" : "Keep something else",
                       detail: "Pin an item in the menu, or choose a folder or file here.",
                       symbol: "plus") {
                Button("Choose…") { chooseFolder() }.buttonStyle(SoftButtonStyle()).pointingCursor()
            }
        }
        Footnote(text: "Everything inside a kept folder is kept too.")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Keep"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.pin(url.path) }
    }
}

private struct KeptRow: View {
    @EnvironmentObject private var store: Store
    let target: String

    var body: some View {
        SettingRow(title: (target as NSString).lastPathComponent,
                   detail: target.hasPrefix("/") ? Format.path(target) : nil,

                   symbol: symbol) {
            Button("Stop keeping") { store.unpin(target) }.buttonStyle(SoftButtonStyle()).pointingCursor()
        }
    }

    private var symbol: String {
        guard target.hasPrefix("/") else { return "shippingbox" }
        return FS.isDirectory(target) ? "folder" : "doc"
    }
}

private struct PermissionsPage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        SectionHeader(title: "Access")
        Card {
            SettingRow(title: "Full Disk Access",
                       detail: store.fullDiskAccess ? "Desktop, Documents, Downloads and the Trash can be checked."
                           : "Desktop, Documents, Downloads and the Trash are skipped until you allow it.",
                       symbol: "lock.shield") {
                HStack(spacing: 8) {
                    StatusPill(text: store.fullDiskAccess ? "Granted" : "Off", good: store.fullDiskAccess)
                    if !store.fullDiskAccess {
                        Button("Set up") { Windows.shared.showOnboarding(step: .access) }
                            .buttonStyle(SoftButtonStyle()).pointingCursor()
                    }
                }
            }
            SettingRow(title: "Background cleaning", detail: backgroundDetail, symbol: "clock") {
                HStack(spacing: 8) {
                    StatusPill(text: backgroundStatus, good: store.agentStatus == .enabled)
                    if store.agentStatus == .requiresApproval {
                        Button("Allow") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(SoftButtonStyle()).pointingCursor()
                    }
                }
            }
        }
        Footnote(text: "Only Mac Janitor itself needs to be in the Full Disk Access list. Its scheduled cleans run as the same app.")
    }

    private var backgroundStatus: String {
        switch store.agentStatus {
        case .enabled: return "Allowed"
        case .requiresApproval: return "Waiting"
        default: return "Not set up"
        }
    }

    private var backgroundDetail: String {
        store.agentStatus == .requiresApproval ? "macOS is waiting for you to allow it in Login Items."
            : "Set up when you turn on automatic cleaning."
    }
}

private struct AboutPage: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        HStack(spacing: 16) {
            AppMark(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Mac Janitor").font(.system(size: TextSize.heading, weight: .semibold))
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.system(size: TextSize.body))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 16)
        SectionHeader(title: "Updates")
        Card {
            SettingRow(title: "Check automatically", detail: "Looks for a new version once a day and asks before installing.") {
                BigToggle(isOn: Binding(get: { updates.checksAutomatically }, set: { updates.checksAutomatically = $0 }))
            }
            SettingRow(title: "Software update", detail: "Install the newest Mac Janitor from GitHub.") {
                Button("Check for Updates…") { updates.check() }
                    .buttonStyle(SoftButtonStyle()).pointingCursor()
                    .disabled(!updates.canCheck)
            }
        }
        SectionHeader(title: "Files")
        Card {
            SettingRow(title: "Settings and reports", detail: Format.path(Paths.support.path)) {
                Button("Show") { NSWorkspace.shared.open(Paths.support) }.buttonStyle(SoftButtonStyle()).pointingCursor()
            }
            SettingRow(title: "Saved work from removed worktrees", detail: "Patches and untracked files, kept for 30 days.") {
                Button("Show") { NSWorkspace.shared.open(Paths.salvage) }.buttonStyle(SoftButtonStyle()).pointingCursor()
            }
        }
    }
}

// MARK: - Controls

struct BigToggle: View {
    let isOn: Binding<Bool>

    var body: some View {
        Toggle("", isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.large)
            .labelsHidden()
            .pointingCursor()
    }
}

private struct ValueStepper: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = "days"

    var body: some View {
        HStack(spacing: 8) {
            Text("\(Format.number(value.wrappedValue)) \(value.wrappedValue == 1 && unit == "days" ? "day" : unit)")
                .font(.system(size: TextSize.body))

                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .pointingCursor()
        }
    }
}

struct Threshold {
    let title: String
    let key: WritableKeyPath<Config, Double>
    var range: ClosedRange<Double> = 1...365
    var step: Double = 1
    var unit = "days"

    static func all(for c: JanitorCore.Category) -> [Threshold] {
        switch c {
        case .worktree:
            return [Threshold(title: "Merged, then idle for", key: \.mergedIdleDays, range: 0...365),
                    Threshold(title: "Pull request open, idle for", key: \.openPRIdleDays),
                    Threshold(title: "Any worktree idle for", key: \.abandonedIdleDays)]
        case .nodeModules: return [Threshold(title: "Worktree idle for", key: \.nodeModulesIdleDays)]
        case .dockerImage: return [Threshold(title: "Unused for", key: \.dockerImageUnusedDays)]
        case .avd: return [Threshold(title: "Unused for", key: \.avdUnusedDays)]
        case .scratchpad: return [Threshold(title: "Untouched for", key: \.scratchpadIdleDays)]
        case .build: return [Threshold(title: "Project unchanged for", key: \.buildIdleDays)]
        case .cache: return [Threshold(title: "Unused for", key: \.cacheIdleDays)]
        case .trash: return [Threshold(title: "In the Trash for", key: \.trashIdleDays)]
        case .largeFile:
            return [Threshold(title: "Bigger than", key: \.largeFileMinGB, range: 0.5...100, step: 0.5, unit: "GB"),
                    Threshold(title: "Unopened for", key: \.largeFileIdleDays)]
        }
    }
}

extension Store {
    func binding<T>(_ key: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { self.config[keyPath: key] }, set: { value in self.update { $0[keyPath: key] = value } })
    }
}

struct RefreshChoice {
    let minutes: Double
    let title: String

    static let all = [
        RefreshChoice(minutes: 15, title: "15 min"),
        RefreshChoice(minutes: 60, title: "1 hour"),
        RefreshChoice(minutes: 360, title: "6 hours"),
    ]
}
