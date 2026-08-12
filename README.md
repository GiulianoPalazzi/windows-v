# Windows V — macOS Clipboard History

Local, offline Windows+V-style clipboard history for macOS. Swift/SwiftUI, menubar-only, no network calls.

- **Hotkey** `Cmd+Shift+V` (Carbon `RegisterEventHotKey`) opens overlay; `Enter` pastes into previously focused app via `CGEvent` `Cmd+V` (requires Accessibility permission; onboarding link to `Privacy_Accessibility`).
- **Capture** `NSPasteboard.general.changeCount` poll (0.4s), TIFF→PNG, text/RTF/image, consecutive dedupe.
- **Storage** `~/Library/Application Support/ClipboardManager/` — `history.sqlite3` (SQLite.swift/WAL) + `images/<uuid>.png`; images stored only on disk.
- **Retention** Unlimited / Capped 100 (2 MB cap, downscale to 1600px) / 24h / 1 week — prunes oldest-first, pinned never pruned; triggers on insert, Settings change, launch. Orphan image cleanup on launch.
- **Chrome** `MenuBarExtra`, Settings (`SMAppService` Launch at Login), `LSUIElement` (no Dock), `NSPanel` overlay (search, pin section, thumbnails via `NSCache`, keyboard nav: ↑/↓ Enter Esc ⌫ ⌘P).

## Build & Run

```bash
open ClipboardManager.xcodeproj
# Run (⌘R) — appears only in menubar. Grant Accessibility when prompted to enable paste.
```

Requires Xcode 26+, macOS 13+, Swift 5. `SQLite.swift` resolved via SPM.

## Icon

Master artwork is `icon/AppIcon.svg` (macOS squircle, clipboard + Apple/Windows split — a port of Win+V). Regenerate every AppIcon size plus a standalone `WindowsV.icns`:

```bash
make icon        # needs rsvg-convert (brew install librsvg)
```

## Distribution

`make` drives a full toolchain: build → sign → package → notarize.

```bash
make build       # Release build -> dist/Windows V.app (ad-hoc signed)
make package     # dist/WindowsV-<version>.zip + .dmg (signed, verified)
make notarize    # Apple notary + staple (needs credentials)
make release     # package + notarize
make version     # bump patch; make version VERSION=1.1.0 to set
make clean
```

Ad-hoc builds run locally. For a Gatekeeper-friendly, distributable build use your Developer ID and notarize:

```bash
make release IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  KEYCHAIN_PROFILE=WindowsV
# or: APPLE_ID=you@x.com APPLE_PASSWORD=app-specific APPLE_TEAM_ID=TEAMID
```

`make package` verifies the code signature inside the zip and the mounted DMG before finishing. Note: paste (CGEvent) needs Accessibility permission — re-grant it after installing a new build.

## Project Layout

```
ClipboardManager/
├── App/   ClipboardManagerApp.swift (MenuBarExtra) / AppDelegate.swift (wiring)
├── Core/  ClipboardMonitor.swift / HistoryStore.swift / HotkeyService.swift / PasteService.swift / AppSupport.swift
├── Models/ ClipboardItem.swift (ClipboardKind, RetentionMode, ClipboardItem)
├── UI/    OverlayWindow.swift (NSPanel) / OverlayView.swift / RowViews.swift + ThumbnailCache / SettingsView.swift
└── Resources/ Info.plist (LSUIElement) / ClipboardManager.entitlements (no sandbox — CGEvent needs it)
icon/       AppIcon.svg (master) + generate_icon.sh + WindowsV.icns
scripts/    build.sh / package.sh / notarize.sh / version.sh / lib.sh
Makefile    target orchestrator
```

## Stretch (not built — per spec)

File copies, HTML/RTF fidelity, OCR, iCloud sync. Also per-app blocklist.

## Slash-goal authoring (learning payoff)

Goal file is `.commandcode/goals/clipboard-manager-goal.md` — frontmatter → Goal → Constraints → Phases with `DELEGATE` blocks. Cheat sheet: `explore` (read-only research), `plan` (schema/design), `general` (isolated slice), inline (UI learning core). Next goal: `per-app blocklist` with same template.
