import SwiftUI

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Windows V", systemImage: "doc.on.clipboard") {
            Button("Open History  ⇧⌘V") { OverlayWindow.shared.toggle() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button("Clear All") { try? delegate.store?.clearAll() }
            Button("Settings…") { delegate.openSettings() }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        Settings {
            if let store = delegate.store {
                SettingsView(store: store)
            } else {
                Text("Loading…")
            }
        }
    }
}
