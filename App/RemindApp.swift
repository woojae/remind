import AppKit
import SwiftUI
import UserNotifications

@main
struct RemindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = TaskStore.shared

    var body: some Scene {
        Window("Remind", id: "main") {
            MainView()
                .environmentObject(store)
        }
        .defaultSize(width: 420, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    NotificationCenter.default.post(name: Notifier.openMainWindow, object: nil)
                }
                .keyboardShortcut("n")
            }
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

/// The status-bar label. It also doubles as the always-alive view that can
/// reopen the main window, since notification handlers have no scene access.
struct MenuBarLabel: View {
    @EnvironmentObject var store: TaskStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = store.now.count
        HStack(spacing: 3) {
            Image(systemName: count > 0 ? "bell.badge.fill" : "bell")
            if count > 0 { Text(String(count)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notifier.openMainWindow)) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: TaskStore

    var body: some View {
        let now = store.now
        if now.isEmpty {
            Text("Nothing due right now")
        } else {
            ForEach(now.prefix(12)) { item in
                Menu(item.title) {
                    Text(Display.when(item, now: store.clock))
                    Button("Done") { store.complete(item) }
                    Divider()
                    SnoozeButtons(item: item)
                }
            }
            if now.count > 12 { Text("…and \(now.count - 12) more") }
        }
        Divider()
        Button("Open Remind") {
            NotificationCenter.default.post(name: Notifier.openMainWindow, object: nil)
        }
        .keyboardShortcut("o")
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Remind") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await TaskStore.shared.start()
            Notifier.shared.start()
        }
    }

    // Closing the window must not stop the nagging — that's the whole point.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: Notifier.openMainWindow, object: nil)
        }
        return true
    }
}
