import AppKit
import Foundation
import UserNotifications

/// Keeps notifying about due tasks until they're completed, snoozed, or
/// deleted. Dismissing a notification changes nothing — it comes back after
/// the repeat interval. Notifications are spaced out so five due tasks never
/// arrive as one pile.
@MainActor
final class Notifier: NSObject, ObservableObject {
    static let shared = Notifier()

    @Published private(set) var authorized: Bool?
    private var timer: Timer?
    private var store: TaskStore { TaskStore.shared }
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    static let openMainWindow = Notification.Name("RemindOpenMainWindow")
    static let openQuickAdd = Notification.Name("RemindOpenQuickAdd")

    func start() {
        guard let center else { return }
        center.delegate = self
        center.setNotificationCategories(Set(Self.categories()))
        Task {
            let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorized = ok
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func refreshAuthorization() {
        guard let center else { return }
        Task {
            let settings = await center.notificationSettings()
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
    }

    // MARK: - Nag loop

    private var lastFullRefresh = Date()

    func tick() {
        store.tick()
        // EventKit changes usually arrive as notifications, but a periodic
        // re-read keeps the list honest if one is missed.
        if Date().timeIntervalSince(lastFullRefresh) > 300 {
            lastFullRefresh = Date()
            Task { await store.refresh() }
        }

        guard store.access == .fullAccess, authorized == true else { return }
        let now = Date()
        guard !Prefs.isQuiet(at: now) else { return }
        if let last = store.state.lastDelivery, now.timeIntervalSince(last) < Prefs.spacing { return }

        let interval = Prefs.repeatInterval
        let candidates = store.now.filter { item in
            guard let last = store.state.lastNotified[item.id] else { return true }
            return now.timeIntervalSince(last) >= interval
        }
        guard let pick = candidates.min(by: {
            (store.state.lastNotified[$0.id] ?? .distantPast) < (store.state.lastNotified[$1.id] ?? .distantPast)
        }) else { return }
        deliver(pick, now: now)
    }

    private func deliver(_ item: TaskItem, now: Date) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        if !item.listName.isEmpty { content.subtitle = item.listName }
        var body = Display.when(item, now: now)
        if item.snoozeCount > 0 { body += " · snoozed \(item.snoozeCount)×" }
        content.body = body
        content.sound = .default
        content.threadIdentifier = "remind"
        content.categoryIdentifier = "task.\(Snooze.suggestedStep(snoozeCount: item.snoozeCount))"
        content.userInfo = ["id": item.id]

        // Re-using the identifier replaces the previous banner for this task
        // instead of stacking a new one under it.
        let request = UNNotificationRequest(identifier: "task.\(item.id)", content: content, trigger: nil)
        center.add(request)
        store.state.lastNotified[item.id] = now
        store.state.lastDelivery = now
    }

    func clear(_ id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: ["task.\(id)"])
        center?.removePendingNotificationRequests(withIdentifiers: ["task.\(id)"])
    }

    // MARK: - Categories

    /// One category per suggested rung. Every category carries the whole
    /// snooze ladder, so the notification offers the same choices as the
    /// app's Snooze menu; the suggested rung is starred, as it is there.
    static func categories() -> [UNNotificationCategory] {
        (0..<Snooze.rungs).map { suggested in
            let snoozes = (0..<Snooze.rungs).map { step in
                UNNotificationAction(
                    identifier: "snooze.\(step)",
                    title: (step == suggested ? "★ " : "") + Snooze.actionTitles[step],
                    options: [])
            }
            return UNNotificationCategory(
                identifier: "task.\(suggested)",
                actions: [UNNotificationAction(identifier: "done", title: "Done", options: [])] + snoozes,
                intentIdentifiers: [],
                options: [])
        }
    }

    private func handle(action: String, id: String) {
        guard let item = store.item(id) else { return }
        let options = Snooze.options()
        switch action {
        case "done":
            store.complete(item)
        case let a where a.hasPrefix("snooze."):
            let step = Int(a.dropFirst("snooze.".count)) ?? 0
            store.snooze(item, until: options[min(max(step, 0), options.count - 1)].date)
        default:
            store.highlighted = id
            NotificationCenter.default.post(name: Self.openMainWindow, object: nil)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if store.highlighted == id { store.highlighted = nil }
            }
        }
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
        let id = response.notification.request.content.userInfo["id"] as? String ?? ""
        await MainActor.run {
            Notifier.shared.handle(action: action, id: id)
        }
    }
}
