import SwiftUI
import AppKit

struct RowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    var onPin: () -> Void
    var onDelete: () -> Void

    var body: some View {
        if item.kind == .image, let url = item.imageFileURL, let nsImage = ThumbnailCache.shared.image(for: url) {
            imageRow(nsImage: nsImage)
        } else {
            textRow
        }
    }

    private func imageRow(nsImage: NSImage) -> some View {
        let maxW = 340.0
        let h = min(160, max(48, nsImage.size.height * min(1, maxW / max(nsImage.size.width, 1))))
        return VStack(spacing: 0) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxW, maxHeight: 160)
                .frame(height: h)
                .clipped()
                .background(Color(nsColor: .controlBackgroundColor))
            rowFooter(item, fontSize: 9)
                .padding(.horizontal, 8).padding(.vertical, 4)
        }
    }

    private var textRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(item.snippet.isEmpty ? "[\(item.kind.rawValue)]" : item.snippet)
                .lineLimit(2).font(.system(size: 12.5)).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.orange) }
            Text(relativeString(item.createdAt)).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
            menuButton(fontSize: 10)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func rowFooter(_ item: ClipboardItem, fontSize: CGFloat) -> some View {
        HStack(spacing: 4) {
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: fontSize)).foregroundStyle(.orange) }
            Text(relativeString(item.createdAt)).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            menuButton(fontSize: fontSize)
        }
    }

    private func menuButton(fontSize: CGFloat) -> some View {
        Menu {
            Button(item.pinned ? "Unpin" : "Pin") { onPin() }
            Button("Delete", role: .destructive) { onDelete() }
        } label: { Image(systemName: "ellipsis").font(.system(size: fontSize)).foregroundStyle(.secondary).frame(width: 16, height: 16) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 16)
    }

    private func relativeString(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 60 { return "\(Int(s))s ago" }
        if s < 3600 { return "\(Int(s/60))m ago" }
        if s < 86400 {
            let h = Int(s/3600); let m = Int((s.truncatingRemainder(dividingBy: 3600))/60)
            return m > 0 ? "\(h)h \(m)m ago" : "\(h)h ago"
        }
        if s < 604800 { return "\(Int(s/86400))d ago" }
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: date)
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    func image(for url: URL, size: CGFloat = 256) -> NSImage? {
        let key = "\(url.path):\(Int(size))" as NSString
        if let c = cache.object(forKey: key) { return c }
        guard let img = NSImage(contentsOf: url) else { return nil }
        let thumb = Self.downscale(img, maxSize: size)
        cache.setObject(thumb, forKey: key)
        return thumb
    }
    static func downscale(_ image: NSImage, maxSize: CGFloat) -> NSImage {
        let s = image.size
        let scale = min(1, maxSize / max(s.width, s.height))
        guard scale < 1 else { return image }
        let newSize = NSSize(width: s.width * scale, height: s.height * scale)
        let out = NSImage(size: newSize)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize))
        out.unlockFocus()
        return out
    }
}
