import AppKit
import SwiftUI

/// Development aid: `Remind --snapshot DIR` renders the main window and the
/// settings window to PNG files in DIR and exits. Draws through the view
/// hierarchy, so it needs no screen-recording permission.
enum Snapshot {
    static var requestedDirectory: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func run(into dir: String, store: TaskStore) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        await capture(SettingsView().environmentObject(store), name: "settings", to: dir)
        await capture(MainView().environmentObject(store).frame(width: 420, height: 600), name: "main", to: dir)
        await capture(QuickAddPanel().environmentObject(store), name: "quickadd", to: dir)
        if let item = store.items.first {
            await capture(EditorView(item: item).environmentObject(store), name: "editor", to: dir)
        }
        exit(0)
    }

    @MainActor
    private static func capture<V: View>(_ view: V, name: String, to dir: String) async {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        try? await Task.sleep(nanoseconds: 800_000_000)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        window.setContentSize(host.frame.size)
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            print("wrote \(dir)/\(name).png \(Int(host.bounds.width))x\(Int(host.bounds.height))")
        }
        window.orderOut(nil)
    }
}
