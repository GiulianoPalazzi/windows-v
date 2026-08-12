import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store: HistoryStore
    @AppStorage("retentionMode") private var retentionRaw = RetentionMode.unlimited.rawValue
    @AppStorage("popupWidth") private var popupWidth = 360.0
    @AppStorage("popupMaxHeight") private var popupMaxHeight = 420.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { v in
                            do { if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                            catch { errorText = error.localizedDescription; launchAtLogin = SMAppService.mainApp.status == .enabled }
                        }
                    if let e = errorText { Text(e).font(.caption).foregroundStyle(.red) }
                } header: { Label("General", systemImage: "gearshape").font(.caption) }

                Section {
                    LabeledContent("Width") {
                        HStack(spacing: 8) {
                            Slider(value: $popupWidth, in: 280...520, step: 20).frame(width: 180)
                            Text("\(Int(popupWidth))").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                        }
                    }
                    LabeledContent("Max Height") {
                        HStack(spacing: 8) {
                            Slider(value: $popupMaxHeight, in: 240...700, step: 20).frame(width: 180)
                            Text("\(Int(popupMaxHeight))").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                        }
                    }
                    Text("Applies on next open.").font(.caption2).foregroundStyle(.secondary)
                } header: { Label("Popup", systemImage: "rectangle").font(.caption) }

                Section {
                    Picker("", selection: Binding(
                        get: { RetentionMode(rawValue: retentionRaw) ?? .unlimited },
                        set: { n in retentionRaw = n.rawValue; try? store.prune(mode: n) }
                    )) {
                        ForEach(RetentionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(currentDetail).font(.caption2).foregroundStyle(.secondary)
                } header: { Label("Keep", systemImage: "archivebox").font(.caption) }

                Section {
                    Button("Open Privacy → Accessibility") { PasteService.openAccessibilitySettings() }
                    PasteStatusRow()
                    Button("Clear All History", role: .destructive) { try? store.clearAllIncludingPinned() }
                    Text("\(store.items.count) items stored").font(.caption2).foregroundStyle(.secondary)
                } header: { Label("Data", systemImage: "internaldrive").font(.caption) }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
        .frame(width: 520, height: 420)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    var currentDetail: String {
        switch RetentionMode(rawValue: retentionRaw) ?? .unlimited {
        case .unlimited: return "Never auto-delete."
        case .capped100: return "100 most recent + pinned. Large images downscaled."
        case .last24h: return "Auto-delete unpinned older than 24 h."
        case .lastWeek: return "Auto-delete unpinned older than 7 d."
        }
    }
}

struct PasteStatusRow: View {
    @State private var trusted = PasteService.isTrusted
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: trusted ? "checkmark.shield.fill" : "exclamationmark.shield")
                .foregroundStyle(trusted ? .green : .orange).font(.caption)
            Text(trusted ? "Pasting enabled" : "Pasting needs Accessibility — dev builds re-sign every rebuild and macOS drops the grant; re-allow via Allow… to regain it.")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            if !trusted {
                Button("Allow…") { _ = PasteService.isAccessibilityTrusted(prompt: true); PasteService.openAccessibilitySettings() }
                    .font(.caption2)
            }
        }
        .task {
            while !Task.isCancelled {
                trusted = PasteService.isTrusted
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
