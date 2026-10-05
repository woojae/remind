import BackgroundTasks
import CoreText
import SwiftUI

/// Remind for iPhone. One screen: the same black panel as the Mac window,
/// with the quick-add field on top and the Now / Later list under it. Settings
/// and the editor come up as sheets.
@main
struct RemindApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = TaskStore.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            PhoneMainView()
                .environmentObject(store)
        }
        .onChange(of: phase) { _, phase in
            switch phase {
            case .active:
                // Coming back to the foreground: re-read Reminders (a task
                // may have been completed on the Mac), and refresh the clock
                // so Now / Later is right.
                store.tick()
                Notifier.shared.refreshAuthorization()
                Task { await store.refresh() }
            case .background:
                // Last chance to extend the nag schedule before suspension.
                Task { await Notifier.shared.rebuild() }
                AppDelegate.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let refreshID = "com.wlee.remind.ios.refresh"

    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Prefs.registerDefaults()
        Fonts.register()
        // The notification delegate has to exist before launch finishes, or a
        // Done / Snooze tapped on a banner while the app was closed is lost.
        Notifier.shared.install()
        return true
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: nil) { task in
            Task { @MainActor in
                task.expirationHandler = { task.setTaskCompleted(success: false) }
                await TaskStore.shared.refresh()
                await Notifier.shared.rebuild()
                AppDelegate.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: true)
            }
        }
        Task { @MainActor in
            await TaskStore.shared.start()
            Notifier.shared.start()
        }
        return true
    }

    /// Asks iOS to wake the app a few hours from now so the pre-scheduled
    /// notifications can be extended further out. iOS treats this as a hint,
    /// not a promise; opening the app always does the same job.
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Registers the bundled fonts (Resources/Fonts) with Core Text at launch.
/// Done in code rather than through UIAppFonts so the same folder layout
/// works for both apps.
enum Fonts {
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
