import AppKit
import EventKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: TaskStore
    @State private var editing: TaskItem?

    var body: some View {
        VStack(spacing: 0) {
            QuickAddBar()
            Divider()
            if store.access == .fullAccess {
                TaskList(editing: $editing)
            } else {
                AccessView()
            }
            if let undo = store.undo {
                UndoBar(record: undo)
            }
        }
        .frame(minWidth: 360, idealWidth: 420, minHeight: 360, idealHeight: 600)
        .sheet(item: $editing) { item in
            EditorView(item: item)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

// MARK: - Quick add

struct QuickAddBar: View {
    @EnvironmentObject var store: TaskStore
    @FocusState private var focused: Bool
    @State private var text = ""

    private var parsed: QuickAdd.Result { QuickAdd.parse(text, now: store.clock) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)
                TextField("Add a task… e.g. “Call mom tomorrow 5pm”", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(submit)
                Button {
                    focused = true
                    NSApp.sendAction(NSSelectorFromString("startDictation:"), to: nil, from: nil)
                } label: {
                    Image(systemName: "mic.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dictate a task")
            }
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 6) {
                    Text(parsed.title).fontWeight(.medium)
                    Text("·").foregroundStyle(.tertiary)
                    Image(systemName: parsed.due == nil ? "bell.fill" : "clock")
                    Text(Display.preview(parsed.due, now: store.clock))
                    Spacer()
                    Text("Return to add").foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.bar)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: Notifier.openMainWindow)) { _ in
            focused = true
        }
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        store.add(value)
        text = ""
    }
}

// MARK: - List

struct TaskList: View {
    @EnvironmentObject var store: TaskStore
    @Binding var editing: TaskItem?

    var body: some View {
        let now = store.now
        let later = store.later
        if now.isEmpty && later.isEmpty {
            ContentUnavailableView {
                Label("Nothing to do", systemImage: "checkmark.circle")
            } description: {
                Text("Add a task above, or say “Hey Siri, remind me to…” on any device.")
            }
        } else {
            List {
                if !now.isEmpty {
                    Section {
                        ForEach(now) { item in
                            TaskRow(item: item, editing: $editing)
                        }
                    } header: {
                        SectionHeader(title: "Now", count: now.count, tint: .orange)
                    }
                }
                if !later.isEmpty {
                    Section {
                        ForEach(later) { item in
                            TaskRow(item: item, editing: $editing)
                        }
                    } header: {
                        SectionHeader(title: "Later", count: later.count, tint: .secondary)
                    }
                }
            }
            .listStyle(.inset)
            .animation(.default, value: store.items)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(tint)
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: TaskStore
    let item: TaskItem
    @Binding var editing: TaskItem?
    @State private var hovering = false

    private var isNow: Bool { item.isNow(at: store.clock) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { store.complete(item) } label: {
                Image(systemName: item.isRecurring ? "arrow.trianglehead.2.clockwise.rotate.90.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isNow ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(item.isRecurring ? "Done for now — schedules the next occurrence from today" : "Mark done")
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(Display.when(item, now: store.clock))
                        .foregroundStyle(isNow ? Color.orange : Color.secondary)
                    if !item.listName.isEmpty {
                        Circle()
                            .fill(item.listColor.map(Color.init) ?? .secondary)
                            .frame(width: 7, height: 7)
                        Text(item.listName)
                    }
                    if item.snoozeCount > 0 {
                        Text("snoozed \(item.snoozeCount)×")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let notes = item.notes {
                    Text(notes).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Menu {
                SnoozeButtons(item: item)
            } label: {
                Image(systemName: "zzz")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering || isNow ? 1 : 0.35)
            .help("Snooze")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .listRowBackground(store.highlighted == item.id ? Color.accentColor.opacity(0.15) : nil)
        .onTapGesture(count: 2) { editing = item }
        .contextMenu {
            Button("Done") { store.complete(item) }
            Menu("Snooze") { SnoozeButtons(item: item) }
            Divider()
            Button("Edit…") { editing = item }
            Menu("Move to") {
                ForEach(store.lists, id: \.calendarIdentifier) { list in
                    Button {
                        store.move(item, to: list.calendarIdentifier)
                    } label: {
                        Text(list.calendarIdentifier == item.listID ? "✓ \(list.title)" : list.title)
                    }
                    .disabled(list.calendarIdentifier == item.listID)
                }
            }
            Button("Open in Reminders") { store.openInReminders(item) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(item) }
        }
    }
}

/// The snooze ladder as menu items. The suggested rung — which climbs each
/// time the task is snoozed — is marked, and every option shows the actual
/// time it lands on.
struct SnoozeButtons: View {
    @EnvironmentObject var store: TaskStore
    let item: TaskItem

    var body: some View {
        let options = Snooze.options(now: store.clock)
        let suggested = Snooze.suggestedStep(snoozeCount: item.snoozeCount)
        ForEach(options) { option in
            Button {
                store.snooze(item, until: option.date)
            } label: {
                Text(label(option, suggested: option.step == suggested))
            }
        }
    }

    private func label(_ option: SnoozeOption, suggested: Bool) -> String {
        let when = Calendar.current.isDate(option.date, inSameDayAs: store.clock)
            ? Display.time(option.date)
            : "\(Display.day(option.date, now: store.clock)) \(Display.time(option.date))"
        return (suggested ? "★ " : "") + "\(option.label)  —  \(when)"
    }
}

// MARK: - Editor

struct EditorView: View {
    @EnvironmentObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    let item: TaskItem

    @State private var title: String
    @State private var dueText: String
    @State private var notes: String
    @State private var listID: String

    init(item: TaskItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _dueText = State(initialValue: Display.editable(item))
        _notes = State(initialValue: item.notes ?? "")
        _listID = State(initialValue: item.listID)
    }

    private var parsedDue: ParsedDate? {
        let t = dueText.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : DateParse.parse(t, now: store.clock)
    }
    private var dueInvalid: Bool {
        !dueText.trimmingCharacters(in: .whitespaces).isEmpty && parsedDue == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Task").font(.headline)
            Form {
                TextField("Title", text: $title)
                VStack(alignment: .leading, spacing: 3) {
                    TextField("When", text: $dueText, prompt: Text("now, tomorrow 9am, friday, +3d…"))
                    Text(dueInvalid ? "Couldn't understand that date." : Display.preview(parsedDue, now: store.clock))
                        .font(.caption)
                        .foregroundStyle(dueInvalid ? Color.red : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(minHeight: 70, maxHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                }
                Picker("List", selection: $listID) {
                    ForEach(store.lists, id: \.calendarIdentifier) { list in
                        Text(list.title).tag(list.calendarIdentifier)
                    }
                }
                if item.isRecurring {
                    Text("Repeats. Completing it schedules the next occurrence from today.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.columns)
            HStack {
                Button("Delete", role: .destructive) {
                    store.delete(item)
                    dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.update(item, title: title, due: parsedDue, notes: notes, listID: listID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || dueInvalid)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: - Undo

struct UndoBar: View {
    @EnvironmentObject var store: TaskStore
    let record: TaskStore.UndoRecord

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(record.item.isRecurring ? "Scheduled next “\(record.item.title)”" : "Completed “\(record.item.title)”")
                .lineLimit(1)
            Spacer()
            Button("Undo") { store.undoComplete() }
                .keyboardShortcut("z", modifiers: .command)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Access

struct AccessView: View {
    @EnvironmentObject var store: TaskStore

    var body: some View {
        ContentUnavailableView {
            Label("Reminders access needed", systemImage: "lock.circle")
        } description: {
            Text("Remind reads and edits your Apple Reminders. Status: \(Auth.name(store.access)).")
        } actions: {
            Button("Request Access") { Task { await store.retryAccess() } }
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
