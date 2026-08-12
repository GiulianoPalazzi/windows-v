import Foundation

enum ClipboardKind: String, Codable, CaseIterable {
    case text
    case rtf
    case image
}

enum RetentionMode: String, CaseIterable, Codable {
    case unlimited
    case capped100
    case last24h
    case lastWeek

    var displayName: String {
        switch self {
        case .unlimited: return "Unlimited"
        case .capped100: return "Last 100"
        case .last24h: return "24 Hours"
        case .lastWeek: return "1 Week"
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let kind: ClipboardKind
    let text: String?
    let rtfData: Data?
    let imageFileName: String?
    var pinned: Bool

    var imageFileURL: URL? {
        guard let name = imageFileName else { return nil }
        return AppSupport.imagesURL.appendingPathComponent(name)
    }

    var displayText: String {
        if let t = text, !t.isEmpty { return t }
        if kind == .image { return "[Image]" }
        return ""
    }

    var snippet: String {
        let s = displayText
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
        if oneLine.count > 80 { return String(oneLine.prefix(80)) + "…" }
        return oneLine
    }
}
