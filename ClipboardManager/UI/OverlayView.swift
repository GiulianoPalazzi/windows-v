import SwiftUI
import AppKit

struct OverlayView: View {
    @ObservedObject var store: HistoryStore
    var onSelect: (ClipboardItem) -> Void
    var onDismiss: () -> Void
    @State private var searchText = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    @State private var selectedID: UUID?
    @State private var scrollOffset = ScrollOffsetPreserver()
    @State private var skipSelectScroll = false
    @State private var hoveredID: UUID?
    @State private var pressedID: UUID?

    var filtered: [ClipboardItem] {
        if searchText.isEmpty { return store.items }
        let q = searchText.lowercased()
        return store.items.filter { ($0.text ?? "").lowercased().contains(q) }
    }
    var pinned: [ClipboardItem] { filtered.filter(\.pinned) }
    var unpinned: [ClipboardItem] { filtered.filter { !$0.pinned } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Clipboard").font(.system(size: 13, weight: .semibold))
                if isSearching {
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($searchFocused)
                        .onSubmit { if let first = filtered.first { onSelect(first) } }
                        .frame(maxWidth: .infinity, maxHeight: 22)
                    Button { searchText = ""; isSearching = false; searchFocused = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                } else {
                    Text("type to search").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { isSearching = true; DispatchQueue.main.async { searchFocused = true } }
            Divider().opacity(isSearching ? 0.4 : 0.3)
            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.title2).foregroundStyle(.secondary)
                    Text(store.items.isEmpty ? "No clipboard history" : "No matches").font(.system(size: 13)).foregroundStyle(.secondary)
                    if store.items.isEmpty { Text("Copy text or images").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if !pinned.isEmpty {
                                sectionHeader("Pinned")
                                ForEach(pinned) { item in row(item).id(item.id).transition(.opacity.combined(with: .move(edge: .top))) }
                                Divider().opacity(0.3).padding(.vertical, 4)
                            }
                            if !pinned.isEmpty, !unpinned.isEmpty { sectionHeader("History") }
                            ForEach(unpinned) { item in row(item).id(item.id).transition(.opacity.combined(with: .move(edge: .top))) }
                        }.padding(.vertical, 4)
                            .background(ScrollOffsetProbe(preserver: scrollOffset))
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: selectedID) { id in
                        if let id, !skipSelectScroll { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
            Divider().opacity(0.3)
            HStack {
                Text("\(filtered.count) items").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("click paste  ⌘P pin  ⌫ del  Esc close").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 8).padding(.vertical, 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { if selectedID == nil { selectedID = filtered.first?.id } }
        .onChange(of: filtered) { items in
            if !skipSelectScroll, selectedID == nil || !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
            // Track the visible count: shrinks when the search narrows or items
            // are deleted, re-expands when the search is cleared / new items
            // appear. updateHeightForFiltered keeps the mouse corner pinned.
            OverlayWindow.shared.updateHeightForFiltered(count: items.count)
        }
        .onChange(of: isSearching) { searching in
            if searching {
                DispatchQueue.main.async { searchFocused = true }
            }
        }
        .background(
            KeyCatcherHolder(
                isSearching: isSearching,
                searchFocused: _searchFocused,
                onEnter: { if let id = selectedID, let item = filtered.first(where: { $0.id == id }) { onSelect(item) } },
                onDelete: {
                    if let id = selectedID { performDelete(id: id) }
                },
                onPin: { if let id = selectedID { try? store.togglePin(id: id) } },
                onEscape: {
                    if isSearching { isSearching = false; searchText = ""; searchFocused = false } else { onDismiss() }
                },
                onUp: {
                    if isSearching, searchFocused {
                        searchFocused = false
                        if selectedID == nil { selectedID = filtered.first?.id }
                        return
                    }
                    guard let idx = filtered.firstIndex(where: { $0.id == selectedID }), idx > 0 else { return }
                    selectedID = filtered[idx - 1].id
                },
                onDown: {
                    if isSearching, searchFocused {
                        searchFocused = false
                        if selectedID == nil { selectedID = filtered.first?.id } else if filtered.firstIndex(where: { $0.id == selectedID }) == nil { selectedID = filtered.first?.id }
                        return
                    }
                    guard let cur = selectedID, let idx = filtered.firstIndex(where: { $0.id == cur }), idx + 1 < filtered.count else {
                        if selectedID == nil, let first = filtered.first { selectedID = first.id }; return
                    }
                    selectedID = filtered[idx + 1].id
                },
                onType: { ch in
                    if !isSearching {
                        searchText = ch
                        isSearching = true
                    } else {
                        // Field not focused yet (transition, or blurred after navigating):
                        // append so the keystroke isn't lost, then re-focus.
                        searchText += ch
                    }
                    DispatchQueue.main.async { searchFocused = true }
                }
            )
            .frame(width: 0, height: 0)
        )
    }

    func sectionHeader(_ s: String) -> some View {
        HStack { Text(s).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase); Spacer() }
            .padding(.horizontal, 10).padding(.vertical, 4)
    }

    func row(_ item: ClipboardItem) -> some View {
        let sel = item.id == selectedID
        let hovered = hoveredID == item.id
        let pressed = pressedID == item.id
        return RowView(item: item, isSelected: sel, onPin: { try? store.togglePin(id: item.id) }, onDelete: {
            performDelete(id: item.id)
        })
            .background(sel ? Color.accentColor.opacity(0.18) : (hovered ? Color.primary.opacity(0.07) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.09), value: pressed)
            .animation(.easeOut(duration: 0.1), value: hovered)
            .onHover { isIn in hoveredID = isIn ? item.id : (hoveredID == item.id ? nil : hoveredID) }
            .onTapGesture {
                selectedID = item.id
                pressedID = item.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                    if pressedID == item.id { pressedID = nil }
                    onSelect(item)
                }
            }
    }

    private func performDelete(id: UUID) {
        let idx = filtered.firstIndex(where: { $0.id == id })
        scrollOffset.capture()
        skipSelectScroll = true
        withAnimation(.easeOut(duration: 0.18)) {
            try? store.delete(id: id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let remaining = filtered
            if remaining.isEmpty { selectedID = nil }
            else if let i = idx, i < remaining.count { selectedID = remaining[i].id }
            else { selectedID = remaining.last?.id }
            skipSelectScroll = false
        }
        scheduleScrollRestore()
    }

    private func scheduleScrollRestore() {
        DispatchQueue.main.async { scrollOffset.restore() }
        for d in [0.06, 0.2, 0.45] {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { scrollOffset.restore() }
        }
    }
}

struct KeyCatcherHolder: NSViewRepresentable {
    var isSearching: Bool
    @FocusState var searchFocused: Bool
    var onEnter: () -> Void
    var onDelete: () -> Void
    var onPin: () -> Void
    var onEscape: () -> Void
    var onUp: () -> Void
    var onDown: () -> Void
    var onType: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = HolderView()
        context.coordinator.holder = v
        v.onEnter = onEnter; v.onDelete = onDelete; v.onPin = onPin
        v.onEscape = onEscape; v.onUp = onUp; v.onDown = onDown; v.onType = onType
        v.isSearchFocused = { searchFocused }
        context.coordinator.install()
        DispatchQueue.main.async {
            if !isSearching { v.window?.makeFirstResponder(v) }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? HolderView else { return }
        v.onEnter = onEnter; v.onDelete = onDelete; v.onPin = onPin
        v.onEscape = onEscape; v.onUp = onUp; v.onDown = onDown; v.onType = onType
        v.isSearchFocused = { searchFocused }
        if !isSearching {
            DispatchQueue.main.async { if v.window?.firstResponder != v { v.window?.makeFirstResponder(v) } }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        weak var holder: HolderView?
        var localMonitor: Any?
        func install() {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak holder] event in
                guard let v = holder, let w = v.window, w.isVisible, w.isKeyWindow else { return event }
                if v.handle(event, searchFocused: v.isSearchFocused?() ?? false) { return nil }
                return event
            }
        }
        deinit { if let m = localMonitor { NSEvent.removeMonitor(m) } }
    }
}

class HolderView: NSView {
    var onEnter: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPin: (() -> Void)?
    var onEscape: (() -> Void)?
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onType: ((String) -> Void)?
    var isSearchFocused: (() -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            if !(self.isSearchFocused?() ?? false) { w.makeFirstResponder(self) }
        }
    }

    func handle(_ event: NSEvent, searchFocused: Bool) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        let isCmd = event.modifierFlags.contains(.command)
        let chars = event.charactersIgnoringModifiers ?? ""
        if event.keyCode == 36 || event.keyCode == 76 { onEnter?(); return true }
        if event.keyCode == 51 || event.keyCode == 117, flags.isEmpty, !searchFocused { onDelete?(); return true }
        if event.keyCode == 53 { onEscape?(); return true }
        if event.keyCode == 126 { onUp?(); return true }
        if event.keyCode == 125 { onDown?(); return true }
        if searchFocused { return false }
        if isCmd && chars.lowercased() == "p" { onPin?(); return true }
        if let s = event.characters, !s.isEmpty, flags.isEmpty, !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            let isPrintable = s.rangeOfCharacter(from: .alphanumerics) != nil || s == " "
            if isPrintable {
                onType?(s)
                // The search field selects all when it (re)gains first responder
                // via FocusState; snap the caret to the end so the next keystroke
                // appends instead of replacing the current query.
                snapSearchCaretToEnd()
                return true
            }
        }
        return false
    }

    private func snapSearchCaretToEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let w = self.window else { return }
            if let field = w.firstResponder as? NSTextField, let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: editor.string.count, length: 0)
            } else if let tv = w.firstResponder as? NSTextView {
                tv.selectedRange = NSRange(location: tv.string.count, length: 0)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if !handle(event, searchFocused: false) { super.keyDown(with: event) }
    }
}

@MainActor
final class ScrollOffsetPreserver {
    private weak var scrollView: NSScrollView?
    private var capturedY: CGFloat?

    func attach(to view: NSView?) {
        var v = view
        while let current = v {
            if let sv = current as? NSScrollView { scrollView = sv; return }
            v = current.superview
        }
    }

    private var offsetY: CGFloat {
        guard let sv = scrollView, sv.documentView != nil else { return 0 }
        return sv.contentView.bounds.minY
    }

    func capture() {
        capturedY = offsetY
    }

    func restore() {
        guard let y = capturedY, let sv = scrollView, let doc = sv.documentView else { return }
        let viewportH = sv.contentView.bounds.height
        let contentH = doc.bounds.height
        let maxY = max(0, contentH - viewportH)
        let target = min(max(0, y), maxY)
        sv.contentView.scroll(to: NSPoint(x: 0, y: target))
    }
}

struct ScrollOffsetProbe: NSViewRepresentable {
    let preserver: ScrollOffsetPreserver

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let v = ProbeView()
        v.onAttach = { [weak preserver] view in preserver?.attach(to: view) }
        context.coordinator.holder = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        preserver.attach(to: nsView)
        DispatchQueue.main.async { [weak preserver] in preserver?.attach(to: nsView) }
    }
    class Coordinator {
        var holder: ProbeView?
    }

    final class ProbeView: NSView {
        var onAttach: ((NSView?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onAttach?(self.ancestorScrollView() ?? self)
            }
        }
        private func ancestorScrollView() -> NSScrollView? {
            var v = superview
            while let current = v {
                if let sv = current as? NSScrollView { return sv }
                v = current.superview
            }
            return nil
        }
    }
}
