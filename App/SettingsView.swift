import AppKit
import EventKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: TaskStore
    @ObservedObject var notifier = Notifier.shared

    @AppStorage(Prefs.Key.repeatMinutes) private var repeatMinutes = 10
    @AppStorage(Prefs.Key.spacingSeconds) private var spacingSeconds = 30
    @AppStorage(Prefs.Key.morningHour) private var morningHour = 9
    @AppStorage(Prefs.Key.quietEnabled) private var quietEnabled = true
    @AppStorage(Prefs.Key.quietStart) private var quietStart = 22
    @AppStorage(Prefs.Key.quietEnd) private var quietEnd = 8
    @AppStorage(Prefs.Key.attachAlarms) private var attachAlarms = true
    @AppStorage(Prefs.Key.excludedLists) private var excludedRaw = "[]"
    @AppStorage(Prefs.Key.defaultList) private var defaultList = ""

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Notifications") {
                Picker("Repeat due tasks every", selection: $repeatMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Space notifications by", selection: $spacingSeconds) {
                    ForEach([10, 30, 60, 120], id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Toggle("Quiet hours", isOn: $quietEnabled)
                LabeledContent("From") {
                    HStack(spacing: 6) {
                        HourPicker(hour: $quietStart)
                        Text("to")
                        HourPicker(hour: $quietEnd)
                    }
                }
                .disabled(!quietEnabled)
                LabeledContent("Morning starts at") {
                    HourPicker(hour: $morningHour)
                }
                Toggle("Set a Reminders alarm too", isOn: $attachAlarms)
                Text("Alarms are what notify your other devices. Reminders.app on this Mac will also show one banner at the due time.")
                    .font(.caption).foregroundStyle(.secondary)
                if notifier.authorized == false {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notifications are turned off for Remind.").foregroundStyle(.red)
                        Button("Open Notification Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            Section("Lists") {
                Picker("Add new tasks to", selection: $defaultList) {
                    Text("Reminders default").tag("")
                    ForEach(store.lists, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
                }
                ForEach(store.lists, id: \.calendarIdentifier) { list in
                    Toggle(list.title, isOn: binding(for: list))
                }
                Text("Unchecked lists are hidden and never notify.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLogin(on) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Text("Remind only notifies while it's running.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .onAppear { notifier.refreshAuthorization() }
        .onChange(of: excludedRaw) { _, _ in Task { await store.refresh() } }
    }

    private func binding(for list: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { !Prefs.excludedLists.contains(list.calendarIdentifier) },
            set: { on in
                var set = Prefs.excludedLists
                if on { set.remove(list.calendarIdentifier) } else { set.insert(list.calendarIdentifier) }
                Prefs.excludedLists = set
                excludedRaw = Prefs.defaults.string(forKey: Prefs.Key.excludedLists) ?? "[]"
            })
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct HourPicker: View {
    @Binding var hour: Int

    var body: some View {
        Picker("", selection: $hour) {
            ForEach(0..<24, id: \.self) { h in
                Text(Self.name(h)).tag(h)
            }
        }
        .labelsHidden()
        .frame(width: 90)
    }

    static func name(_ h: Int) -> String {
        let df = DateFormatter()
        df.dateFormat = "h a"
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
        return df.string(from: d)
    }
}
