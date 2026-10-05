import EventKit
import SwiftUI

/// The Mac settings window, as a sheet. Same keys, so a choice made here
/// means the same thing it does on the Mac. No "launch at login": the nag
/// schedule is handed to the system and runs whether the app is open or not.
struct PhoneSettingsView: View {
    @EnvironmentObject var store: TaskStore
    @ObservedObject var notifier = Notifier.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.Key.repeatMinutes) private var repeatMinutes = 10
    @AppStorage(Prefs.Key.spacingSeconds) private var spacingSeconds = 30
    @AppStorage(Prefs.Key.morningHour) private var morningHour = 9
    @AppStorage(Prefs.Key.quietEnabled) private var quietEnabled = true
    @AppStorage(Prefs.Key.quietStart) private var quietStart = 22
    @AppStorage(Prefs.Key.quietEnd) private var quietEnd = 8
    @AppStorage(Prefs.Key.attachAlarms) private var attachAlarms = true
    @AppStorage(Prefs.Key.excludedLists) private var excludedRaw = "[]"
    @AppStorage(Prefs.Key.defaultList) private var defaultList = ""

    var body: some View {
        NavigationStack {
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
                    Text("Alarms are what notify your other devices. With Remind on this phone, the Reminders app's own banner here is redundant; turn it off in Settings › Notifications › Reminders.")
                        .font(.caption).foregroundStyle(.secondary)
                    if notifier.authorized == false {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notifications are turned off for Remind.").foregroundStyle(.red)
                            Button("Open Notification Settings") { Platform.openNotificationSettings() }
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

                Section("Schedule") {
                    LabeledContent("Queued with iOS", value: "\(notifier.scheduledCount) notifications")
                    if let until = notifier.scheduledUntil {
                        LabeledContent("Planned through",
                                       value: "\(Display.day(until, now: store.clock)) \(Display.time(until))")
                    }
                    Text("iOS fires these whether or not Remind is open. Opening the app, or acting on a banner, plans the next stretch. Quiet hours are built into the plan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.windowBG)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .themedWindow()
        .onAppear { notifier.refreshAuthorization() }
        .onChange(of: excludedRaw) { _, _ in Task { await store.refresh() } }
        .onChange(of: repeatMinutes) { _, _ in notifier.scheduleRebuild() }
        .onChange(of: spacingSeconds) { _, _ in notifier.scheduleRebuild() }
        .onChange(of: quietEnabled) { _, _ in notifier.scheduleRebuild() }
        .onChange(of: quietStart) { _, _ in notifier.scheduleRebuild() }
        .onChange(of: quietEnd) { _, _ in notifier.scheduleRebuild() }
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
}
