import AppKit

final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastString: String?
    private var lastImageHash: Int?
    var onNewItem: ((ClipboardKind, String?, Data?, Data?) -> Void)?

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        // Skip changes we made ourselves (paste / select-to-paste) so we don't
        // re-record the item as a brand-new copy.
        if pb.changeCount == PasteService.lastWrittenChangeCount {
            lastChangeCount = pb.changeCount
            return
        }
        lastChangeCount = pb.changeCount

        if let data = pb.data(forType: .tiff), let image = NSImage(data: data),
           let tiff = image.tiffRepresentation {
            let hash = tiff.hashValue
            if hash == lastImageHash { return }
            lastImageHash = hash
            lastString = nil
            let png = Self.tiffToPNG(tiff) ?? tiff
            onNewItem?(.image, nil, nil, png)
            return
        }

        if let str = pb.string(forType: .string), !str.isEmpty {
            if str == lastString { return }
            lastString = str
            lastImageHash = nil
            if let rtf = pb.data(forType: .rtf) {
                onNewItem?(.rtf, str, rtf, nil)
            } else {
                onNewItem?(.text, str, nil, nil)
            }
            return
        }

        if let rtf = pb.data(forType: .rtf) {
            let str = pb.string(forType: .string) ?? ""
            if str == lastString { return }
            lastString = str
            onNewItem?(.rtf, str.isEmpty ? nil : str, rtf, nil)
        }
    }

    static func tiffToPNG(_ tiff: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
