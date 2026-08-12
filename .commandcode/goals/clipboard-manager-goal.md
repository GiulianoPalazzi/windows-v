---
name: macos-clipboard-history
description: Build a local, offline macOS Windows+V clipboard history (Swift/SwiftUI, text+images) — learn slash-goal authoring with agent delegation.
version: 1
---

# Goal: macOS Windows+V Clipboard History

Build a local, offline macOS clipboard history app at `windows-v/` that mirrors **Windows+V**.
Stack: **Swift + SwiftUI**, menubar-only (`LSUIElement`), overlay on **Cmd+Shift+V**.
You will learn slash-goal authoring by doing it: this file *is* the prompt the agent executes.

## How a slash goal works (read this — you're learning the tool)

A slash goal is a markdown file with frontmatter that `/goal <name>` executes as an agentic session.
Structure: `frontmatter (name/description/version)` → `Goal` → `Constraints` → `Phases` with explicit delegation.
The orchestrator expands each phase and spawns sub-agents where instructed. Agent outputs are reviewed before moving on.
After this file runs, inspect it: every `DELEGATE` block is a pattern you can reuse for your own goals.

## Constraints (from plan — do not change scope without asking)

- **Types:** Text + Images only (TIFF/PNG). Capture everything (no blocklist in v1).
- **Features:** Search + Pin + Delete + Clear All; paste-directly-to-app via `CGEvent`.
- **Retention Settings:** Unlimited (default) / Capped 100 (2 MB image cap, downscale) / 24h / 1 week — prunes oldest-first, pinned items never pruned.
- **Storage:** `~/Library/Application Support/<App>/images/<uuid>.png` + SQLite index (`SQLite.swift` or SwiftData). Retention logic runs on insert, on Settings change, and on launch.
- **Chrome:** `MenuBarExtra`, Settings window, Launch at Login via `SMAppService`, `LSUIElement` (no Dock).
- **Paste:** Requires Accessibility permission — onboarding sheet with System Settings deep link.
- **Privacy:** Local-only, no network calls, images on disk only.

## Phases — follow in order, delegate exactly as instructed

### Phase 1 — Scaffold (DELEGATE: explore agent)

> **DELEGATE to an explore sub-agent:**
> Prompt: "Explore how to scaffold a SwiftUI menubar-only app (LSUIElement, MenuBarExtra, Settings scene, SMAppService for Launch at Login) and recommend SPM deps for global hotkeys on macOS. Return file paths, Info.plist keys, entitlements, and a minimal App scaffold snippet."
> Why explore? Research-heavy, read-only discovery — the agent returns paths/snippets without writing.

Then create the Xcode project at `windows-v/ClipboardManager/` (or SPM app), set `LSUIElement=true`, add SPM deps (`KeyboardShortcuts` preferred, fallback `HotKey`; `SQLite.swift`), create `Application Support/<App>/` helper, stub `SMAppService` toggle, and verify the app launches menubar-only (no Dock).

**Done when:** `ClipboardManager` builds and appears only in the menubar.

### Phase 2 — Clipboard capture (DELEGATE: general agent)

> **DELEGATE to a general sub-agent:**
> Prompt: "Implement `Core/ClipboardMonitor.swift` that polls `NSPasteboard.general.changeCount` every 0.4s on the main run loop, extracts `string`/`rtf`/`tiff`→PNG in priority order, dedupes consecutive identical entries, and calls `HistoryStore.add(_:)`. Include a unit test for dedupe (same text twice → one entry, text→image→same text → two entries)."
> Why general? Well-specified, isolated implementation slice that can be reviewed as a unit.

Review the agent's output, wire `ClipboardMonitor` to `HistoryStore` (in-memory array first is fine), and verify copies appear in logs/list.

**Done when:** Copying text and an image in any app appends entries to the store (visible in debug list/logs).

### Phase 3 — Persistence + retention (DELEGATE: plan agent)

> **DELEGATE to a plan sub-agent:**
> Prompt: "Design `Core/HistoryStore.swift` persistence: SQLite index + file-backed images. Detail the table schema for `ClipboardItem { id, createdAt, kind, text, rtfData, imageFileURL, pinned }`, file layout under `Application Support/<App>/images/`, CRUD, and `prune()` for four retention modes (unlimited / capped100 / last24h / lastWeek) with 'never prune pinned' and image file cleanup. Note migration when the user switches modes."
> Why plan? Forces schema + prune review before coding; catches retention edge cases early.

Then implement the design: SQLite table, image write (TIFF→PNG, downscale if capped mode), `add`/`delete`/`togglePin`/`clearAll`/`prune()`, Settings picker binding (`UserDefaults` for `RetentionMode`), and prune triggers (on insert, on Settings change, on launch). Test each mode switch and relaunch persistence.

**Done when:** History survives relaunch; switching Unlimited/Capped/24h/Week prunes correctly and deletes orphan image files; pinned items survive all prunes.

### Phase 4 — Overlay UI (NO delegation — you build inline)

This is the SwiftUI learning core — build it inline so you see the UI loop directly.
Create `NSPanel` (`nonactivatingPanel`, `floating`, `worksWhenModal`, hides on deactivate) hosting `OverlayView` via `NSHostingView`.
`OverlayView`: search field (focused on open), pinned section on top, virtualized list (`List` or `LazyVStack`) with `TextRow` (snippet, timestamp) and `ImageRow` (256 px thumbnail, lazy load), keyboard nav (↑/↓, Enter, Esc, ⌫), actions: Enter = paste, Delete = remove, Cmd+P = pin, Esc = dismiss. Remember `previousApp = NSWorkspace.shared.frontmostApplication` before showing overlay.
Trigger via menubar "Open History" first; hotkey comes next phase.

**Done when:** Overlay opens from menubar, shows searchable history with text snippets and image thumbnails, supports keyboard nav and pin/delete.

### Phase 5 — Hotkey + Paste (DELEGATE: explore + general)

> **DELEGATE to an explore sub-agent:**
> Prompt: "Find the correct `KeyboardShortcuts` (or `HotKey`) registration for global Cmd+Shift+V and the `CGEvent` paste pattern (`CGEvent(keyboardEventSource:virtualKey:keyDown:)`, `CGEventPost`) with `AXIsProcessTrustedWithOptions` onboarding and the System Settings deep link `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. Return minimal snippets."
> Why explore? API surface is narrow and docs-heavy — the agent collects the exact calls.

> **DELEGATE to a general sub-agent:**
> Prompt: "Implement `Core/HotkeyService.swift` (register Cmd+Shift+V via KeyboardShortcuts/HotKey) and `Core/PasteService.swift` (write selected item to NSPasteboard with correct type, hide overlay, reactivate previous app, 30–60 ms delay then synthesize Cmd+V via CGEvent). Include the Accessibility permission check and onboarding sheet trigger."
> Why general? Isolated services with clear interfaces to HistoryStore and Overlay.

Wire: hotkey → show overlay; overlay pick → `PasteService.paste(item)` → pastes into previously focused app. Handle permission denied (show sheet) vs granted (paste succeeds).

**Done when:** Cmd+Shift+V opens overlay; picking an entry pastes it into TextEdit/Notes; permission-denied path shows onboarding.

### Phase 6 — Polish + QA (DELEGATE: general agent)

> **DELEGATE to a general sub-agent:**
> Prompt: "Add thumbnail caching (downscaled 256 px, NSCache), image compression for capped mode (>2 MB → max 1600 px long edge), Launch at Login toggle wiring (SMAppService), empty state, app icon, and run the QA matrix: text / multiline / emoji / large image / rapid copies / retention switches / sleep-wake / permission denied. Report findings as a checklist with fixes."
> Why general? Polish is parallelizable and benefits from a QA checklist the main session can triage.

Fix findings, then do a final manual pass of the full flow.

**Done when:** Thumbnails are cached, capped images are compressed, Launch at Login toggles, empty state shows, and the QA matrix passes.

## Acceptance (all must pass)

- [ ] Copies of text and images appear in history and survive relaunch.
- [ ] `Cmd+Shift+V` opens searchable overlay; `Enter` pastes into the previously focused app.
- [ ] Pin/Delete/Clear All work; pinned items survive every retention prune.
- [ ] Settings switches Unlimited / Capped 100 / 24h / 1 week and prunes correctly; Launch at Login toggles.
- [ ] No network calls; images stored only on disk under Application Support.

## Stretch (out of scope — note in README, do not build)

File copies, HTML/RTF fidelity, OCR for images, iCloud sync.

## Reflection (do this after the build — this is the learning payoff)

- Open this file and annotate which `DELEGATE` blocks saved time vs which you would inline next time.
- Try authoring a second goal (e.g. "add per-app blocklist") using the same frontmatter → Goal → Constraints → Phases pattern and run it with `/goal <your-new-name>`.

## Reference implementation structure

```
windows-v/
├── ClipboardManager.xcodeproj
├── ClipboardManager/
│   ├── App/
│   │   ├── ClipboardManagerApp.swift
│   │   └── AppDelegate.swift
│   ├── Core/
│   │   ├── ClipboardMonitor.swift
│   │   ├── HistoryStore.swift
│   │   ├── HotkeyService.swift
│   │   └── PasteService.swift
│   ├── UI/
│   │   ├── OverlayWindow.swift
│   │   ├── OverlayView.swift
│   │   ├── RowViews.swift
│   │   └── SettingsView.swift
│   ├── Models/
│   │   └── ClipboardItem.swift
│   └── Resources/
│       └── Info.plist
└── .commandcode/
    ├── goals/
    │   └── clipboard-manager-goal.md  ← this file
    └── taste/taste.md
```

## Useful commands

- Run the goal: `/goal macos-clipboard-history`
- Check goal status: `/goal status`
- Clear goal: `/goal clear`
- Inspect plan: `/plans` → select `macos-clipboard-history-windows-v`

## Agent delegation cheat sheet (for your next goal)

- **explore** → research-heavy, read-only ("find the API / pattern / file").
- **plan** → design/decision before coding ("detail the schema / tradeoffs").
- **general** → isolated, well-specified build slice ("implement X.swift with tests").
- **inline (no agent)** → learning-critical or tightly coupled UI you want to touch yourself.
