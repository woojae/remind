import AppKit
import EventKit
import Foundation

/// One row in the list. A value copy of the EKReminder, so views never touch
/// EventKit objects directly.
struct TaskItem: Identifiable, Equatable {
    let id: String
    var title: String
    var notes: String?
    var listName: String
    var listID: String
    var listColor: NSColor?
    /// Effective due moment. All-day reminders resolve to the morning hour.
    var due: Date?
    var isAllDay: Bool
    let isRecurring: Bool
    let created: Date?
    var snoozeCount: Int

    func isNow(at now: Date) -> Bool { due.map { $0 <= now } ?? true }
}

/// Everything the UI and the notifier need, backed by the shared EventKit wrapper.
@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published private(set) var items: [TaskItem] = []
    @Published private(set) var lists: [EKCalendar] = []
    @Published private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    @Published var clock = Date()
    @Published var errorMessage: String?
    @Published var undo: UndoRecord?
    @Published var highlighted: String?

    struct UndoRecord: Equatable {
        let item: TaskItem
        let previousDue: DateComponents?
    }

    let ek = Reminders()
    private var reminders: [String: EKReminder] = [:]
    private var refreshTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?

    var state = StateFile.load() {
        didSet { StateFile.save(state) }
    }

    var now: [TaskItem] {
        items.filter { $0.isNow(at: clock) }
            .sorted { ($0.due ?? $0.created ?? .distantPast) < ($1.due ?? $1.created ?? .distantPast) }
    }

    var later: [TaskItem] {
        items.filter { !$0.isNow(at: clock) }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    func item(_ id: String) -> TaskItem? { items.first { $0.id == id } }

    // MARK: - Lifecycle

    func start() async {
        access = (try? await ek.requestAccess()) ?? EKEventStore.authorizationStatus(for: .reminder)
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: ek.store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        await refresh()
    }

    /// Coalesces the burst of change notifications EventKit sends per save.
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func retryAccess() async {
        access = (try? await ek.requestAccess()) ?? EKEventStore.authorizationStatus(for: .reminder)
        await refresh()
    }

    func refresh() async {
        guard access == .fullAccess else { return }
        lists = ek.lists()
        let excluded = Prefs.excludedLists
        let included = lists.filter { !excluded.contains($0.calendarIdentifier) }
        guard !included.isEmpty else {
            items = []
            reminders = [:]
            return
        }
        let found = await ek.fetch(in: included, includeCompleted: false, onlyCompleted: false)
        var map: [String: EKReminder] = [:]
        for r in found { map[r.calendarItemIdentifier] = r }
        reminders = map
        state.prune(keeping: Set(map.keys))
        items = found.map(makeItem)
        clock = Date()
        updateBadge()
    }

    func tick() {
        clock = Date()
        updateBadge()
    }

    /// All-day reminders are shown as due at the morning hour.
    private static func effectiveDue(_ date: Date?, isAllDay: Bool) -> Date? {
        date.map { d in
            guard isAllDay else { return d }
            return Calendar.current.date(bySettingHour: Prefs.morningHour, minute: 0, second: 0, of: d) ?? d
        }
    }

    private func makeItem(_ r: EKReminder) -> TaskItem {
        let color = r.calendar?.cgColor.flatMap { NSColor(cgColor: $0) }
        return TaskItem(
            id: r.calendarItemIdentifier,
            title: r.title?.isEmpty == false ? r.title! : "(untitled)",
            notes: r.notes?.isEmpty == false ? r.notes : nil,
            listName: r.calendar?.title ?? "",
            listID: r.calendar?.calendarIdentifier ?? "",
            listColor: color,
            due: Self.effectiveDue(r.dueDate, isAllDay: r.isAllDay),
            isAllDay: r.isAllDay,
            isRecurring: r.hasRecurrenceRules,
            created: r.creationDate,
            snoozeCount: state.snoozeCount[r.calendarItemIdentifier] ?? 0)
    }

    // MARK: - Optimistic updates
    //
    // EventKit saves synchronously but the change notification that triggers
    // a refresh is debounced, so the list would otherwise lag every action by
    // about half a second. Apply the expected result locally first; the
    // refresh that follows reconciles against what EventKit actually stored.

    private func updateBadge() {
        NSApp.dockTile.badgeLabel = now.isEmpty ? nil : String(now.count)
    }

    private func removeLocal(_ id: String) {
        items.removeAll { $0.id == id }
        updateBadge()
    }

    private func replaceLocal(_ item: TaskItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.append(item)
        }
        updateBadge()
    }

    // MARK: - Actions

    private func attempt(_ body: () throws -> Void) {
        do { try body() } catch { errorMessage = "\(error)" }
    }

    func add(_ text: String) {
        let parsed = QuickAdd.parse(text)
        guard !parsed.title.isEmpty else { return }
        attempt {
            let calendar: EKCalendar
            if let c = lists.first(where: { $0.calendarIdentifier == Prefs.defaultList }) {
                calendar = c
            } else {
                calendar = try ek.resolveList(nil)
            }
            let r = EKReminder(eventStore: ek.store)
            r.calendar = calendar
            r.title = parsed.title
            if let due = parsed.due {
                r.setDue(due, attachAlarm: Prefs.attachAlarms)
            }
            try ek.save(r)
            // An undated task is due now; give it one full interval before the first nag.
            if parsed.due == nil { state.lastNotified[r.calendarItemIdentifier] = Date() }
        }
        scheduleRefresh()
    }

    func complete(_ item: TaskItem) {
        guard let r = reminders[item.id] else { return }
        attempt {
            let previous = r.dueDateComponents
            var updated: TaskItem?
            if r.hasRecurrenceRules, let rule = r.recurrenceRules?.first {
                // Skip every missed occurrence: the next one is measured from now,
                // not from the date you were supposed to do it.
                let base = r.dueDate ?? Date()
                let next = Self.nextOccurrence(after: Date(), from: base, rule: rule)
                r.setDue(ParsedDate(date: next, hasTime: !r.isAllDay), attachAlarm: Prefs.attachAlarms)
                var copy = item
                copy.due = Self.effectiveDue(next, isAllDay: r.isAllDay)
                copy.snoozeCount = 0
                updated = copy
            } else {
                r.isCompleted = true
            }
            try ek.save(r)
            state.forget(item.id)
            Notifier.shared.clear(item.id)
            if let updated { replaceLocal(updated) } else { removeLocal(item.id) }
            offerUndo(UndoRecord(item: item, previousDue: previous))
        }
        scheduleRefresh()
    }

    func undoComplete() {
        guard let record = undo else { return }
        undo = nil
        attempt {
            let r: EKReminder?
            if let cached = reminders[record.item.id] {
                r = cached
            } else {
                r = ek.store.calendarItem(withIdentifier: record.item.id) as? EKReminder
            }
            guard let r else { return }
            if r.hasRecurrenceRules {
                r.dueDateComponents = record.previousDue
            } else {
                r.isCompleted = false
            }
            try ek.save(r)
            state.snoozeCount[record.item.id] = record.item.snoozeCount
            replaceLocal(record.item)
        }
        scheduleRefresh()
    }

    private func offerUndo(_ record: UndoRecord) {
        undo = record
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.undo == record { self?.undo = nil }
        }
    }

    func snooze(_ item: TaskItem, until date: Date) {
        guard let r = reminders[item.id] else { return }
        attempt {
            r.setDue(ParsedDate(date: date, hasTime: true), attachAlarm: Prefs.attachAlarms)
            try ek.save(r)
            state.snoozeCount[item.id, default: 0] += 1
            state.lastNotified[item.id] = nil
            Notifier.shared.clear(item.id)
            var copy = item
            copy.due = date
            copy.isAllDay = false
            copy.snoozeCount = state.snoozeCount[item.id] ?? 0
            replaceLocal(copy)
        }
        scheduleRefresh()
    }

    /// Explicit reschedule from the editor. Resets the snooze ladder.
    func update(_ item: TaskItem, title: String, due: ParsedDate?, notes: String, listID: String? = nil) {
        guard let r = reminders[item.id] else { return }
        attempt {
            var copy = item
            r.title = title.trimmingCharacters(in: .whitespaces)
            r.notes = notes.isEmpty ? nil : notes
            copy.title = r.title?.isEmpty == false ? r.title! : "(untitled)"
            copy.notes = r.notes
            if let listID, listID != item.listID,
               let target = lists.first(where: { $0.calendarIdentifier == listID }) {
                r.calendar = target
                copy.listID = target.calendarIdentifier
                copy.listName = target.title
                copy.listColor = target.cgColor.flatMap { NSColor(cgColor: $0) }
            }
            let changedDue = due?.date != r.dueDate || (due == nil) != (r.dueDate == nil)
            if changedDue {
                r.setDue(due, attachAlarm: Prefs.attachAlarms)
                state.forget(item.id)
                Notifier.shared.clear(item.id)
                copy.isAllDay = due.map { !$0.hasTime } ?? false
                copy.due = Self.effectiveDue(due?.date, isAllDay: copy.isAllDay)
                copy.snoozeCount = 0
            }
            try ek.save(r)
            replaceLocal(copy)
        }
        scheduleRefresh()
    }

    func move(_ item: TaskItem, to listID: String) {
        guard let r = reminders[item.id],
              let target = lists.first(where: { $0.calendarIdentifier == listID }) else { return }
        attempt {
            r.calendar = target
            try ek.save(r)
            var copy = item
            copy.listID = target.calendarIdentifier
            copy.listName = target.title
            copy.listColor = target.cgColor.flatMap { NSColor(cgColor: $0) }
            replaceLocal(copy)
        }
        scheduleRefresh()
    }

    func delete(_ item: TaskItem) {
        guard let r = reminders[item.id] else { return }
        attempt {
            try ek.remove(r)
            state.forget(item.id)
            Notifier.shared.clear(item.id)
            removeLocal(item.id)
        }
        scheduleRefresh()
    }

    func openInReminders(_ item: TaskItem) {
        if let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(item.id)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Recurrence

    static func nextOccurrence(after now: Date, from base: Date, rule: EKRecurrenceRule, cal: Calendar = .current) -> Date {
        let interval = max(1, rule.interval)
        let weekdays = Set((rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue })

        if rule.frequency == .weekly, !weekdays.isEmpty {
            // Walk day by day until we land on an allowed weekday in the future.
            var d = base
            for _ in 0..<(400 * 7) {
                d = cal.date(byAdding: .day, value: 1, to: d)!
                if d > now, weekdays.contains(cal.component(.weekday, from: d)) { return d }
            }
            return d
        }

        let component: Calendar.Component
        switch rule.frequency {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        @unknown default: component = .day
        }
        var d = base
        for _ in 0..<2000 {
            d = cal.date(byAdding: component, value: interval, to: d)!
            if d > now { return d }
        }
        return d
    }
}
