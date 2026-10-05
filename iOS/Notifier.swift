import Combine
import Foundation
import UIKit
import UserNotifications

/// The phone's counterpart to the Mac notifier, with the same job: keep
/// notifying about due tasks until each is completed, snoozed, or deleted.
///
/// iOS suspends the app seconds after it leaves the screen, so there is no
/// timer to nag from. Instead, every change to the list rebuilds a schedule
/// of future notifications and hands it to the system: for each task, one
/// request per repeat interval, spaced apart from the others, skipping quiet
/// hours, for as far ahead as the request budget reaches. Done / Snooze on a
/// banner run in the background and rebuild the schedule again.
@MainActor
final class Notifier: NSObject, ObservableObject {
    static let shared = Notifier()

    @Published private(set) var authorized: Bool?
    /// What is currently queued with the system, for the settings screen.
    @Published private(set) var scheduledCount = 0
    @Published private(set) var scheduledUntil: Date?

    static let openMainWindow = Notification.Name("RemindOpenMainWindow")
    static let openQuickAdd = Notification.Name("RemindOpenQuickAdd")

    /// iOS keeps at most 64 pending requests per app; leave a little headroom.
    static let budget = 60
    static let horizon: TimeInterval = 24 * 60 * 60

    private var store: TaskStore { TaskStore.shared }
    private let center = UNUserNotificationCenter.current()
    private var subscriptions = Set<AnyCancellable>()
    private var rebuildTask: Task<Void, Never>?
    private var clockTimer: Timer?

    /// The fire times handed to the system last time, per task. Anything in
    /// here that is now in the past was shown, whether or not the banner is
    /// still around to prove it. Survives relaunches.
    private var planned: [String: [Date]] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "plannedNags"),
                  let value = try? JSONDecoder().decode([String: [Date]].self, from: data) else { return [:] }
            return value
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "plannedNags")
        }
    }

    // MARK: - Lifecycle

    /// Synchronous part of start-up: called from willFinishLaunching so the
    /// delegate is in place before a background action response arrives.
    func install() {
        center.delegate = self
        center.setNotificationCategories(Set(Self.categories()))
    }

    func start() {
        Task {
            let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorized = ok
            scheduleRebuild()
        }
        store.$items
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRebuild() }
            .store(in: &subscriptions)
        // Keeps "Since 3:15 PM" and the Now / Later split honest while the
        // app is on screen. Stops with the app; nothing depends on it.
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.tick() }
        }
    }

    func refreshAuthorization() {
        Task {
            let settings = await center.notificationSettings()
            let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if ok != authorized {
                authorized = ok
                scheduleRebuild()
            }
        }
    }

    /// Takes down the banner for a task that was just completed, snoozed, or
    /// deleted. Pending requests are rebuilt wholesale, so only delivered
    /// ones need removing by hand.
    func clear(_ id: String) {
        Task {
            let delivered = await center.deliveredNotifications()
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix("task.\(id).") }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
        scheduleRebuild()
    }

    // MARK: - Scheduling

    /// Coalesces the burst of changes a single edit produces.
    func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.rebuild()
        }
    }

    /// Replaces everything pending with a fresh plan from the current list.
    func rebuild() async {
        rebuildTask?.cancel()
        guard store.access == .fullAccess, authorized == true else { return }
        absorbPlanned()
        await absorbDelivered()
        center.removeAllPendingNotificationRequests()

        let now = Date()
        let slots = plan(now: now)
        planned = Dictionary(grouping: slots, by: \.item.id).mapValues { $0.map(\.date) }
        for slot in slots {
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, slot.date.timeIntervalSince(now)), repeats: false)
            let request = UNNotificationRequest(identifier: slot.identifier,
                                                content: content(for: slot.item, at: slot.date),
                                                trigger: trigger)
            try? await center.add(request)
        }
        scheduledCount = slots.count
        scheduledUntil = slots.last?.date
    }

    struct Slot {
        let item: TaskItem
        let date: Date
        let identifier: String
    }

    /// The Mac decides what to show at each 15-second tick; this works out
    /// the same decisions ahead of time. Each task gets a nag every repeat
    /// interval from when it falls due (or from its last nag); the streams
    /// are merged in time order, pushed apart by the spacing setting, pushed
    /// past quiet hours, and cut off at the budget.
    func plan(now: Date) -> [Slot] {
        let interval = Prefs.repeatInterval
        let spacing = Prefs.spacing
        let end = now.addingTimeInterval(Self.horizon)

        var candidates: [(Date, TaskItem)] = []
        for item in store.items {
            var t: Date
            if let due = item.due, due > now {
                t = due
            } else {
                let last = store.state.lastNotified[item.id] ?? .distantPast
                t = max(now.addingTimeInterval(2), last.addingTimeInterval(interval))
            }
            while t <= end {
                candidates.append((t, item))
                t = t.addingTimeInterval(interval)
            }
        }
        candidates.sort { $0.0 < $1.0 }

        var slots: [Slot] = []
        var previous = store.state.lastDelivery ?? .distantPast
        var previousForItem: [String: Date] = [:]
        var counter: [String: Int] = [:]
        for (date, item) in candidates {
            var t = max(date, previous.addingTimeInterval(spacing))
            t = Prefs.nextAllowed(after: t)
            guard t <= end else { continue }
            // Two nags pushed to the same end of quiet hours collapse into one.
            if let p = previousForItem[item.id], t.timeIntervalSince(p) < interval - 1 { continue }
            let n = counter[item.id, default: 0]
            counter[item.id] = n + 1
            slots.append(Slot(item: item, date: t, identifier: "task.\(item.id).\(n)"))
            previous = t
            previousForItem[item.id] = t
            if slots.count >= Self.budget { break }
        }
        return slots
    }

    private func content(for item: TaskItem, at fire: Date) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.title
        if !item.listName.isEmpty { content.subtitle = item.listName }
        var body = Display.when(item, now: fire)
        if item.snoozeCount > 0 { body += " · snoozed \(item.snoozeCount)×" }
        content.body = body
        content.sound = .default
        content.threadIdentifier = item.id
        content.categoryIdentifier = "task.\(Snooze.suggestedStep(snoozeCount: item.snoozeCount))"
        content.userInfo = ["id": item.id]
        return content
    }

    /// The system fires the schedule without telling us. Every planned fire
    /// time that has passed counts as a nag that happened, so a banner the
    /// user swiped away still holds off the next one for a full interval.
    private func absorbPlanned() {
        let now = Date()
        var state = store.state
        for (id, dates) in planned {
            for date in dates where date <= now {
                if (state.lastNotified[id] ?? .distantPast) < date { state.lastNotified[id] = date }
                if (state.lastDelivery ?? .distantPast) < date { state.lastDelivery = date }
            }
        }
        store.state = state
    }

    /// Banners still on screen are read back too: older ones for the same
    /// task are collapsed into the newest, and banners for tasks no longer
    /// due (completed on another device, say) are taken down.
    private func absorbDelivered() async {
        let delivered = await center.deliveredNotifications()
        guard !delivered.isEmpty else { return }
        var state = store.state
        var stale: [String] = []
        var newest: [String: UNNotification] = [:]
        let now = Date()
        for n in delivered {
            guard let id = n.request.content.userInfo["id"] as? String else { continue }
            guard let item = store.item(id), item.isNow(at: now) else {
                stale.append(n.request.identifier)
                continue
            }
            if (state.lastNotified[id] ?? .distantPast) < n.date { state.lastNotified[id] = n.date }
            if (state.lastDelivery ?? .distantPast) < n.date { state.lastDelivery = n.date }
            if let current = newest[id] {
                if n.date > current.date {
                    stale.append(current.request.identifier)
                    newest[id] = n
                } else {
                    stale.append(n.request.identifier)
                }
            } else {
                newest[id] = n
            }
        }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
        store.state = state
    }

    // MARK: - Categories and actions

    /// One category per snooze rung, so the button can say exactly how long.
    static func categories() -> [UNNotificationCategory] {
        (0..<Snooze.rungs).map { step in
            let alt = step < Snooze.morningStep ? "Tomorrow morning" : "Snooze 1 hour"
            return UNNotificationCategory(
                identifier: "task.\(step)",
                actions: [
                    UNNotificationAction(identifier: "done", title: "Done", options: []),
                    UNNotificationAction(identifier: "snooze", title: Snooze.actionTitles[step], options: []),
                    UNNotificationAction(identifier: "alt", title: alt, options: []),
                ],
                intentIdentifiers: [],
                options: [])
        }
    }

    private func handle(action: String, category: String, id: String) async {
        // A banner action can launch the app in the background, before the
        // store has read anything.
        if store.item(id) == nil { await store.refresh() }
        guard let item = store.item(id) else { return }
        let step = Int(category.split(separator: ".").last ?? "") ?? 0
        let options = Snooze.options()
        switch action {
        case "done":
            store.complete(item)
        case "snooze":
            store.snooze(item, until: options[min(step, options.count - 1)].date)
        case "alt":
            store.snooze(item, until: options[step < Snooze.morningStep ? Snooze.morningStep : 2].date)
        default:
            store.highlighted = id
            NotificationCenter.default.post(name: Self.openMainWindow, object: nil)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if store.highlighted == id { store.highlighted = nil }
            }
            return
        }
        // The store's own refresh is debounced; in the background there may
        // be no later moment, so re-plan now while the system is still waiting.
        await store.refresh()
        await rebuild()
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let id = response.notification.request.content.userInfo["id"] as? String ?? ""
        await Notifier.shared.handle(action: action, category: category, id: id)
    }
}
