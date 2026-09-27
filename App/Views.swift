import AppKit
import EventKit
import SwiftUI

// MARK: - Main window

/// The main window is one of woojae.com's windows, edge to edge: a dark
/// title bar carrying the wordmark (and the macOS traffic lights), then the
/// white body.
struct MainView: View {
    @EnvironmentObject var store: TaskStore
    @State private var editing: TaskItem?

    var body: some View {
        DesktopWindow(title: "remind",
                      trailing: store.now.isEmpty ? nil : "\(store.now.count) due now",
                      mark: true, titlebarHeight: Theme.chromeTitlebarHeight, floating: false) {
            QuickAddBar()
            Rule()
            if store.access == .fullAccess {
                TaskList(editing: $editing)
            } else {
                AccessView()
            }
            Rule()
            StatusBar()
        }
        .frame(minWidth: 340, idealWidth: 420, minHeight: 380, idealHeight: 600)
        // The hidden title bar still reserves its height as safe area;
        // the dark bar has to run right up to the top edge.
        .ignoresSafeArea(edges: .top)
        .background(Theme.windowBG.ignoresSafeArea())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .themedWindow { window in
            window.backgroundColor = NSColor(Theme.titlebar)
        }
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

/// `.window-statusbar`: what's due, or the undo line right after completing.
struct StatusBar: View {
    @EnvironmentObject var store: TaskStore

    var body: some View {
        HStack(spacing: 8) {
            if let undo = store.undo {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                Text(undo.item.isRecurring ? "Scheduled next “\(undo.item.title)”" : "Completed “\(undo.item.title)”")
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                Button("Undo") { store.undoComplete() }
                    .buttonStyle(LinkButtonStyle())
                    .keyboardShortcut("z", modifiers: .command)
            } else {
                Text(summary)
                Spacer()
                Text("⌘N  new task")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .animation(.default, value: store.undo != nil)
    }

    private var summary: String {
        let now = store.now.count, later = store.later.count
        let first = now == 0 ? "Nothing due now" : "\(now) due now"
        return later == 0 ? first : "\(first) · \(later) later"
    }
}

// MARK: - Quick add

struct QuickAddBar: View {
    @EnvironmentObject var store: TaskStore
    @FocusState private var focused: Bool
    @State private var text = ""
    /// Called after a task is added; the floating panel uses it to close.
    var onAdded: (() -> Void)? = nil

    private var parsed: QuickAdd.Result { QuickAdd.parse(text, now: store.clock) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.muted)
                TextField("Add a task… “Call mom tomorrow 5pm”", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .onSubmit(submit)
                Button {
                    focused = true
                    NSApp.sendAction(NSSelectorFromString("startDictation:"), to: nil, from: nil)
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .help("Dictate a task")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.field))

            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 6) {
                    Text(parsed.title).foregroundStyle(Theme.ink)
                    Text("·")
                    Image(systemName: parsed.due == nil ? "bell.fill" : "clock")
                    Text(Display.preview(parsed.due, now: store.clock))
                    Spacer()
                    Text("Return to add")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 12)
            }
        }
        .padding(16)
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
        onAdded?()
    }
}

/// The compact floating panel opened from the menu bar. Just the quick-add
/// field: type, Return, gone.
struct QuickAddPanel: View {
    @EnvironmentObject var store: TaskStore
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        DesktopWindow(title: "New Task",
                      trailing: store.now.isEmpty ? "Nothing due now" : "\(store.now.count) due now",
                      titlebarHeight: Theme.chromeTitlebarHeight, floating: false) {
            QuickAddBar(onAdded: { dismissWindow(id: "quickadd") })
            Rule()
            HStack {
                Text("Return to add · Esc to cancel")
                Spacer()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 480)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onExitCommand { dismissWindow(id: "quickadd") }
        .themedWindow { window in
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(Theme.titlebar)
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.makeKeyAndOrderFront(nil)
        }
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
            MarkHeadline(mark: "all clear.",
                         sub: "Add a task above, or say “Hey Siri, remind me to…” on any device.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !now.isEmpty {
                        SectionLabel(title: "Now", count: now.count, tint: Theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)
                        ForEach(now) { item in
                            TaskRow(item: item, editing: $editing)
                        }
                    }
                    if !later.isEmpty {
                        SectionLabel(title: "Later", count: later.count)
                            .padding(.horizontal, 10)
                            .padding(.top, now.isEmpty ? 0 : 18)
                            .padding(.bottom, 6)
                        ForEach(later) { item in
                            TaskRow(item: item, editing: $editing)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .animation(.default, value: store.items)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// `.link-row`: bold title, quieter detail line, a soft accent wash on hover.
struct TaskRow: View {
    @EnvironmentObject var store: TaskStore
    let item: TaskItem
    @Binding var editing: TaskItem?
    @State private var hovering = false

    private var isNow: Bool { item.isNow(at: store.clock) }

    private var rowBackground: Color {
        if store.highlighted == item.id { return Theme.highlight }
        return hovering ? Theme.hover : .clear
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { store.complete(item) } label: {
                Image(systemName: item.isRecurring ? "arrow.trianglehead.2.clockwise.rotate.90.circle" : "circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isNow ? Theme.accent : Theme.muted)
            }
            .buttonStyle(.plain)
            .help(item.isRecurring ? "Done for now — schedules the next occurrence from today" : "Mark done")
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(Display.when(item, now: store.clock))
                        .fontWeight(isNow ? .semibold : .regular)
                        .foregroundStyle(isNow ? Theme.accent : Theme.body)
                    if !item.listName.isEmpty {
                        Circle()
                            .fill(item.listColor.map(Color.init) ?? Theme.muted)
                            .frame(width: 7, height: 7)
                        Text(item.listName)
                    }
                    if item.snoozeCount > 0 {
                        Text("snoozed \(item.snoozeCount)×")
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                if let notes = item.notes {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Menu {
                SnoozeButtons(item: item)
            } label: {
                Image(systemName: "zzz")
                    .foregroundStyle(Theme.muted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering || isNow ? 1 : 0.4)
            .help("Snooze")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(rowBackground))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
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

/// A small window of its own, with the site's close dot standing in for Cancel.
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
    private var saveDisabled: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty || dueInvalid
    }

    var body: some View {
        DesktopWindow(title: "Edit Task", onClose: { dismiss() }, floating: false) {
            VStack(alignment: .leading, spacing: 16) {
                FieldBox(label: "Title") {
                    TextField("Title", text: $title)
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldBox(label: "When") {
                        TextField("When", text: $dueText, prompt: Text("now, tomorrow 9am, friday, +3d…"))
                    }
                    Text(dueInvalid ? "Couldn't understand that date." : Display.preview(parsedDue, now: store.clock))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(dueInvalid ? Theme.danger : Theme.muted)
                        .padding(.leading, 2)
                }
                FieldBox(label: "Notes") {
                    TextEditor(text: $notes)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 64, maxHeight: 130)
                        .padding(.horizontal, -5)
                }
                HStack {
                    Text("LIST")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Picker("List", selection: $listID) {
                        ForEach(store.lists, id: \.calendarIdentifier) { list in
                            Text(list.title).tag(list.calendarIdentifier)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                if item.isRecurring {
                    Text("Repeats. Completing it schedules the next occurrence from today.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.body)
                }
                HStack(spacing: 10) {
                    Button("Delete") {
                        store.delete(item)
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.danger)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        store.update(item, title: title, due: parsedDue, notes: notes, listID: listID)
                        dismiss()
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(saveDisabled)
                    .opacity(saveDisabled ? 0.45 : 1)
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(width: 440)
        .themedWindow()
    }
}

// MARK: - Access

struct AccessView: View {
    @EnvironmentObject var store: TaskStore

    var body: some View {
        VStack(spacing: 22) {
            MarkHeadline(mark: "hello.",
                         sub: "Remind reads and edits your Apple Reminders.\nStatus: \(Auth.name(store.access)).")
            HStack(spacing: 10) {
                Button("Request Access") { Task { await store.retryAccess() } }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                Button("System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}
