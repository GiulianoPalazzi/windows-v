import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var store: HistoryStore?
    var monitor: ClipboardMonitor?
    var hotkeyService: HotkeyService?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: this LSUIElement app owns a global hotkey and a
        // menu bar slot, so a second copy must not register them. If another
        // instance is already running, focus it and exit instead of fighting.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.windowsv.ClipboardManager"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let mine = running.first { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier }
        let others = running.filter { $0.processIdentifier != mine?.processIdentifier }
        if let firstOther = others.first {
            firstOther.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        do {
            let s = try HistoryStore()
            store = s
            OverlayWindow.shared.configure(store: s)
        } catch {
            NSLog("HistoryStore init failed: \(error)")
        }
        let m = ClipboardMonitor()
        m.onNewItem = { [weak self] kind, text, rtf, imageData in
            DispatchQueue.main.async {
                try? self?.store?.add(text: text, rtfData: rtf, imageData: imageData, kind: kind)
            }
        }
        m.start()
        monitor = m
        PasteService.startTrustMonitor()
        let hk = HotkeyService()
        hk.register { OverlayWindow.shared.toggle() }
        hotkeyService = hk
    }

    func openSettings() {
        if let w = settingsWindow, w.isVisible { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        guard let store else { return }
        let view = SettingsView(store: store)
        let hosting = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.contentView = hosting
        w.title = "Windows V Settings"
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = w
    }
}
