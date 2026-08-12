import AppKit
import SwiftUI

class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayWindow: NSObject {
    static let shared = OverlayWindow()
    private var panel: OverlayPanel?
    private var previousApp: NSRunningApplication?
    var store: HistoryStore?
    private var currentAnchor: Anchor = .bottomLeft
    private var globalClickMonitor: Any?

    var width: CGFloat {
        let w = UserDefaults.standard.double(forKey: "popupWidth")
        return w > 0 ? CGFloat(w) : 360
    }
    var maxHeight: CGFloat {
        let h = UserDefaults.standard.double(forKey: "popupMaxHeight")
        return h > 0 ? CGFloat(h) : 420
    }
    private let gap: CGFloat = 12
    private let headerHeight: CGFloat = 40
    private let footerHeight: CGFloat = 24

    enum Anchor { case bottomLeft, bottomRight, topLeft, topRight }

    func configure(store: HistoryStore) { self.store = store }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        if panel == nil { createPanel() }
        guard let p = panel else { return }
        refreshHosting()
        let h = currentHeight()
        p.setContentSize(NSSize(width: width, height: h))
        if let vev = p.contentView as? NSVisualEffectView {
            vev.frame = NSRect(origin: .zero, size: NSSize(width: width, height: h))
            if let hosting = vev.subviews.first as? NSHostingView<OverlayView> {
                hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: h))
            }
        }
        currentAnchor = chooseAnchor(for: p.frame.size)
        position(panel: p, anchor: currentAnchor)
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        // Menubar/LSUIElement apps need to become active for the panel to be
        // brought to the front; without this the floating panel can appear
        // behind the active app's windows.
        NSApp.activate(ignoringOtherApps: false)
        p.makeKey()
        DispatchQueue.main.async {
            func findHolder(_ v: NSView) -> NSView? {
                if v is HolderView { return v }
                for c in v.subviews { if let f = findHolder(c) { return f } }
                return nil
            }
            if let vev = p.contentView as? NSVisualEffectView,
               let hosting = vev.subviews.first(where: { $0 is NSHostingView<OverlayView> }),
               let found = findHolder(hosting) ?? (p.contentView.flatMap { findHolder($0) }) {
                p.makeFirstResponder(found)
            }
        }
    }

    func hide() { panel?.orderOut(nil) }

    func pasteAndHide(item: ClipboardItem) {
        let target = previousApp
        hide()
        // Give the target a tick to regain key after our panel ordered out, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40)) {
            PasteService.refreshTrust()
            if !PasteService.isTrusted {
                // Guide the user at most once per launch; repeatedly stealing
                // focus to System Settings is hostile, and the Settings window
                // already exposes status + an "Allow…" action.
                if !PasteService.didOpenAXSettingsThisLaunch {
                    PasteService.didOpenAXSettingsThisLaunch = true
                    PasteService.openAccessibilitySettings()
                }
                target?.activate(options: [.activateAllWindows])
                return
            }
            PasteService.paste(item: item, to: target)
        }
    }

    private func refreshHosting() {
        guard let p = panel, let vev = p.contentView as? NSVisualEffectView, let store else { return }
        vev.subviews.forEach { if $0 is NSHostingView<OverlayView> { $0.removeFromSuperview() } }
        let view = OverlayView(store: store, onSelect: { [weak self] item in self?.pasteAndHide(item: item) }, onDismiss: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: currentHeight()))
        hosting.autoresizingMask = [.width, .height]
        vev.addSubview(hosting)
    }

    private func currentHeight() -> CGFloat {
        guard let s = store else { return 200 }
        return contentHeight(count: MainActor.assumeIsolated { s.items.count })
    }

    private func contentHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 140 }
        let rowH: CGFloat = 48
        let total = headerHeight + CGFloat(count) * rowH + 8 + footerHeight
        return min(max(total, 120), maxHeight)
    }

    func updateHeightForFiltered(count: Int) {
        guard let p = panel, p.isVisible else { return }
        let newH = contentHeight(count: count)
        guard abs(p.frame.height - newH) > 1 else { return }
        let oldH = p.frame.height
        var frame = p.frame
        frame.size.height = newH
        // Keep the corner nearest the mouse pinned so the panel grows/shrinks
        // away from the cursor. Bottom anchors (panel above the mouse) fix the
        // bottom edge; top anchors (panel below the mouse) fix the top edge.
        if currentAnchor == .topLeft || currentAnchor == .topRight {
            frame.origin.y += oldH - newH
        }
        p.setFrame(frame, display: true, animate: true)
        if let vev = p.contentView as? NSVisualEffectView {
            vev.frame = NSRect(origin: .zero, size: NSSize(width: width, height: newH))
            if let h = vev.subviews.first as? NSHostingView<OverlayView> { h.frame = vev.bounds }
        }
    }

    private func chooseAnchor(for size: NSSize) -> Anchor {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return .bottomLeft }
        let vf = screen.visibleFrame
        let spaceRight = vf.maxX - (mouse.x + gap)
        let spaceLeft = (mouse.x - gap) - vf.minX
        let spaceAbove = vf.maxY - (mouse.y + gap)
        let spaceBelow = (mouse.y - gap) - vf.minY
        let fitsRight = spaceRight >= size.width
        let fitsLeft = spaceLeft >= size.width
        let fitsAbove = spaceAbove >= size.height
        let fitsBelow = spaceBelow >= size.height
        if fitsAbove && fitsRight { return .bottomLeft }
        if fitsAbove && fitsLeft { return .bottomRight }
        if fitsBelow && fitsRight { return .topLeft }
        if fitsBelow && fitsLeft { return .topRight }
        if fitsAbove { return fitsRight ? .bottomLeft : .bottomRight }
        if fitsBelow { return fitsRight ? .topLeft : .topRight }
        return .bottomLeft
    }

    private func position(panel p: NSPanel, anchor: Anchor) {
        let mouse = NSEvent.mouseLocation
        let size = p.frame.size
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            p.center(); return
        }
        let vf = screen.visibleFrame
        var origin: NSPoint
        switch anchor {
        case .bottomLeft:
            origin = NSPoint(x: mouse.x + gap, y: mouse.y + gap)
        case .bottomRight:
            origin = NSPoint(x: mouse.x - gap - size.width, y: mouse.y + gap)
        case .topLeft:
            origin = NSPoint(x: mouse.x + gap, y: mouse.y - gap - size.height)
        case .topRight:
            origin = NSPoint(x: mouse.x - gap - size.width, y: mouse.y - gap - size.height)
        }
        origin.x = max(vf.minX + 6, min(origin.x, vf.maxX - size.width - 6))
        origin.y = max(vf.minY + 6, min(origin.y, vf.maxY - size.height - 6))
        p.setFrameOrigin(origin)
    }

    private func createPanel() {
        let p = OverlayPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: width, height: 200)),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.hidesOnDeactivate = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        let vev = NSVisualEffectView(frame: p.contentRect(forFrameRect: p.frame))
        vev.material = .popover
        vev.blendingMode = .behindWindow
        vev.state = .active
        vev.wantsLayer = true
        vev.layer?.cornerRadius = 12
        vev.layer?.masksToBounds = true
        vev.layer?.borderWidth = 0.5
        vev.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        p.contentView = vev
        self.panel = p
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.panel?.isVisible == true { self?.hide() }
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.panel?.isVisible == true { DispatchQueue.main.async { self?.hide() } }
        }
        // Keep previousApp pinned to the last frontmost app that isn't us, so
        // pasting works even when the overlay is opened from our own menu bar
        // (where `frontmostApplication` can momentarily resolve to us).
        NotificationCenter.default.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.previousApp = app
        }
    }
}
