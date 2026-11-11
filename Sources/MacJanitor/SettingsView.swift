import AppKit
import JanitorCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(spacing: 0) {
            if let problem = store.problem {
                ProblemBanner(text: problem) { store.problem = nil }
                    .padding([.horizontal, .top], 16)
            }
            Form {
                AutomaticSection()
                PermissionsSection()
                Section {
                    ForEach(JanitorCore.Category.allCases, id: \.self) { CategorySettings(category: $0) }
                } header: {
                    Text("What to clean")
                } footer: {
                    Text("Turned-off categories are not checked or cleaned. Everything is shown before a manual clean.")
                }
                KeptSection()
                GeneralSection()
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 640)
    }
}

private struct AutomaticSection: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { store.automatic }, set: { store.setAutomatic($0) })) {
                Text("Clean automatically")
                Text(store.automatic ? "Runs in the background, even with the menu closed." : "Off. Nothing is removed unless you click Clean.")
            }
            .pointingCursor()
            Picker("How often", selection: store.binding(\.intervalHours)) {
                ForEach(ScheduleChoice.all, id: \.hours) { Text($0.title).tag($0.hours) }
                if !ScheduleChoice.all.contains(where: { $0.hours == store.config.intervalHours }) {
                    Text("Every \(Format.number(store.config.intervalHours)) hours").tag(store.config.intervalHours)
                }
            }
            .disabled(!store.automatic)
            ValueStepper(title: "Clean early when free space is below", value: store.binding(\.lowDiskGB),
                         range: 5...200, step: 5, unit: "GB")
                .disabled(!store.automatic)
            if store.agentStatus == .requiresApproval {
                HStack {
                    Label("macOS needs your OK to run Mac Janitor in the background.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .pointingCursor()
                }
            }
        } header: {
            Text("Automatic cleaning")
        }
    }
}

private struct PermissionsSection: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Section {
            HStack {
                Image(systemName: store.fullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(store.fullDiskAccess ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access")
                    Text(store.fullDiskAccess ? "Granted" : "Off: Desktop, Documents, Downloads and the Trash are skipped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !store.fullDiskAccess {
                    Button("Set up…") { Windows.shared.showOnboarding(step: .access) }
                        .pointingCursor()
                }
            }
        } header: {
            Text("Permissions")
        }
        .task { await store.refreshAccess() }
    }
}

/// A category's switch, what it means, and the age at which things go.
private struct CategorySettings: View {
    @EnvironmentObject private var store: Store
    let category: JanitorCore.Category

    var body: some View {
        let enabled = store.config.enabled(category)
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { enabled }, set: { store.setEnabled(category, $0) })) {
                Label(category.title, systemImage: category.symbol)
            }
            .pointingCursor()
            Text(category.explanation(store.config))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if enabled {
                ForEach(Threshold.all(for: category), id: \.title) { t in
                    ValueStepper(title: t.title, value: store.binding(t.key), range: t.range, step: t.step, unit: t.unit)
                        .padding(.leading, 28)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct Threshold {
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

private struct ValueStepper: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = "days"

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Format.number(value.wrappedValue)) \(value.wrappedValue == 1 && unit == "days" ? "day" : unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper(title, value: value, in: range, step: step)
                .labelsHidden()
                .pointingCursor()
        }
        .font(.callout)
    }
}

private struct KeptSection: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Section {
            if store.config.keep.isEmpty {
                Text("Nothing yet. Use the pin next to an item in the menu to keep it.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.config.keep, id: \.self) { target in
                HStack {
                    Image(systemName: "pin.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((target as NSString).lastPathComponent).lineLimit(1)
                        Text(Format.path(target))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Stop keeping") { store.update { $0.keep.removeAll { $0 == target } } }
                        .pointingCursor()
                }
            }
        } header: {
            Text("Kept items")
        }
    }
}

private struct GeneralSection: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Section {
            Toggle("Open Mac Janitor at login", isOn: Binding(get: { store.loginStatus.isOn }, set: { store.setLaunchAtLogin($0) }))
                .pointingCursor()
            HStack {
                Button("Show setup guide") { Windows.shared.showOnboarding() }
                    .pointingCursor()
                Button("Open activity log") { store.openLog() }
                    .pointingCursor()
                Spacer()
                Button("Quit Mac Janitor") { NSApp.terminate(nil) }
                    .pointingCursor()
            }
        } header: {
            Text("General")
        }
    }
}

extension Store {
    func binding<T>(_ key: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(get: { self.config[keyPath: key] }, set: { value in self.update { $0[keyPath: key] = value } })
    }
}
