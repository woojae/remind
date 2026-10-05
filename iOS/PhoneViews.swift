import SwiftUI

/// The whole phone app on one screen: the Mac window, edge to edge, minus the
/// traffic lights. The editor and Settings are sheets.
struct PhoneMainView: View {
    @EnvironmentObject var store: TaskStore
    @State private var editing: TaskItem?
    @State private var showSettings = false

    var body: some View {
        DesktopWindow(title: "remind",
                      trailing: store.now.isEmpty ? nil : "\(Theme.readout(store.now.count)) due",
                      mark: true, floating: false) {
            QuickAddBar()
            Rule()
            if store.access == .fullAccess {
                TaskList(editing: $editing)
            } else {
                AccessView()
            }
            Rule()
            StatusBar(onSettings: { showSettings = true })
        }
        // The panel keeps to the safe area; the black runs under the status
        // bar and home indicator. The layout stays put when the keyboard rises.
        .background(Theme.windowBG.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
        .themedWindow()
        .sheet(item: $editing) { item in
            EditorView(item: item)
                .environmentObject(store)
                .presentationBackground(Theme.windowBG)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSettings) {
            PhoneSettingsView()
                .environmentObject(store)
                .presentationBackground(Theme.windowBG)
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
