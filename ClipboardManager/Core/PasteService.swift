import AppKit
import Carbon.HIToolbox
import ApplicationServices

enum PasteService {
    /// changeCount of the most recent pasteboard write performed by us, so the
    /// clipboard monitor can avoid re-recording it as a brand-new copy.
    static var lastWrittenChangeCount: Int = -1

    /// Cached AX trust state, refreshed every second by `startTrustMonitor()`.
    /// Decision paths read this cache instead of re-checking with a prompt, so
    /// the app never pops the system Accessibility dialog on its own — it only
    /// opens System Settings (no dialog) when paste is genuinely unavailable.
    static private(set) var isTrusted: Bool = isAccessibilityTrusted()
    private static var trustTimer: Timer?

    /// Whether System Settings' Accessibility pane has already been opened once
    /// this launch, so an untrusted app doesn't keep yanking the user out.
    static var didOpenAXSettingsThisLaunch = false

    static func startTrustMonitor() {
        refreshTrust()
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in refreshTrust() }
    }

    static func refreshTrust() {
        isTrusted = isAccessibilityTrusted()
    }

    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func paste(item: ClipboardItem, to app: NSRunningApplication?) {
        let pb = NSPasteboard.general
        write(item, to: pb)
        lastWrittenChangeCount = pb.changeCount

        guard let target = resolveTarget(app) else { return }

        // Hand focus to the target for the synthesized Cmd+V. Our app is an
        // LSUIElement menubar app: after the panel orders out, this app often
        // *remains* the frontmost application. Bringing the target forward is
        // desirable anyway so the pasted content is visible to the user, and
        // .activateIgnoringOtherApps is what reliably steals focus away from
        // our own still-frontmost app.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != target.bundleIdentifier {
            target.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        // The keystroke is posted through the HID tap, which only reaches the
        // target's performKeyEquivalent: once it's truly frontmost — poll
        // instead of guessing a fixed settle delay.
        waitForFrontmost(target, attemptsLeft: 25) {
            postCmdV(item: item, to: target)
        }
    }

    private static func waitForFrontmost(_ target: NSRunningApplication, attemptsLeft: Int, then: @escaping () -> Void) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier || attemptsLeft <= 0 {
            then()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
            waitForFrontmost(target, attemptsLeft: attemptsLeft - 1, then: then)
        }
    }

    /// Picking a target to paste into. Falls back to the frontmost app, but
    /// never resolves to our own app (e.g. when the overlay was opened from
    /// the menu bar, where the frontmost app can be us) — pasting into
    /// ourselves would silently swallow the Cmd+V.
    private static func resolveTarget(_ app: NSRunningApplication?) -> NSRunningApplication? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidate = app ?? NSWorkspace.shared.frontmostApplication
        guard let candidate, candidate.processIdentifier != ownPID else { return nil }
        return candidate
    }

    private static func postCmdV(item: ClipboardItem, to target: NSRunningApplication) {
        let pb = NSPasteboard.general
        if pb.changeCount != lastWrittenChangeCount {
            write(item, to: pb)
            lastWrittenChangeCount = pb.changeCount
        }
        if !isTrusted { return }
        synthesizeCmdV(to: target)
    }

    private static func write(_ item: ClipboardItem, to pb: NSPasteboard) {
        pb.clearContents()
        switch item.kind {
        case .image:
            if let url = item.imageFileURL, let image = NSImage(contentsOf: url) {
                pb.writeObjects([image])
            } else if let text = item.text {
                pb.setString(text, forType: .string)
            }
        case .rtf:
            if let rtf = item.rtfData {
                pb.setData(rtf, forType: .rtf)
                pb.setString(item.text ?? "", forType: .string)
            } else if let t = item.text {
                pb.setString(t, forType: .string)
            }
        case .text:
            pb.setString(item.text ?? "", forType: .string)
            if let rtf = item.rtfData {
                pb.setData(rtf, forType: .rtf)
            }
        }
    }

    static func synthesizeCmdV(to target: NSRunningApplication) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        vUp?.flags = .maskCommand
        // Post through the HID tap, not postToPid: postToPid delivers below the
        // window-server event path that performKeyEquivalent: reads from, so
        // many apps (TextEdit included) silently drop it. By this point
        // waitForFrontmost has confirmed target is actually key, so the HID tap
        // reaches it reliably.
        vDown?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
            vUp?.post(tap: .cghidEventTap)
        }
    }
}
