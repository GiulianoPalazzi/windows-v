import Foundation
import SQLite
import ImageIO
import CoreGraphics

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    var retentionMode: RetentionMode {
        get { RetentionMode(rawValue: UserDefaults.standard.string(forKey: "retentionMode") ?? RetentionMode.unlimited.rawValue) ?? .unlimited }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "retentionMode") }
    }

    private var db: Connection?
    private let dbURL: URL
    private let imagesDir: URL

    private let table = Table("clipboard_items")
    private let colID = Expression<String>("id")
    private let colCreatedAt = Expression<Date>("created_at")
    private let colKind = Expression<String>("kind")
    private let colText = Expression<String?>("text")
    private let colRtfData = Expression<Data?>("rtf_data")
    private let colImageFileName = Expression<String?>("image_filename")
    private let colPinned = Expression<Bool>("pinned")

    init(dbURL: URL? = nil, imagesDirectory: URL? = nil) throws {
        self.dbURL = dbURL ?? AppSupport.dbURL
        self.imagesDir = imagesDirectory ?? AppSupport.imagesURL
        try AppSupport.ensureDirectories()
        try openDB()
        try migrate()
        try loadFromDB()
        try pruneIfNeeded()
        try cleanupOrphanImages()
    }

    init(inMemoryForTesting: Bool) throws {
        self.dbURL = URL(fileURLWithPath: ":memory:")
        self.imagesDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        if inMemoryForTesting {
            db = try Connection(.inMemory)
            try db!.run("PRAGMA journal_mode = WAL")
            try migrate()
        }
    }

    private func openDB() throws {
        db = try Connection(dbURL.path)
        try db!.run("PRAGMA journal_mode = WAL")
        try db!.run("PRAGMA foreign_keys = ON")
    }

    private func migrate() throws {
        guard let db else { return }
        try db.run(table.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colCreatedAt)
            t.column(colKind)
            t.column(colText)
            t.column(colRtfData)
            t.column(colImageFileName)
            t.column(colPinned, defaultValue: false)
        })
        try db.run(table.createIndex(colCreatedAt, ifNotExists: true))
        try db.run(table.createIndex([colPinned, colCreatedAt], ifNotExists: true))
    }

    private func loadFromDB() throws {
        guard let db else { return }
        let rows = try db.prepare(table.order(colCreatedAt.desc))
        items = try rows.map(rowToItem)
    }

    private func rowToItem(_ row: Row) throws -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: row[colID]) ?? UUID(),
            createdAt: row[colCreatedAt],
            kind: ClipboardKind(rawValue: row[colKind]) ?? .text,
            text: row[colText],
            rtfData: row[colRtfData],
            imageFileName: row[colImageFileName],
            pinned: row[colPinned]
        )
    }

    func reload() throws { try loadFromDB() }

    @discardableResult
    func add(text: String? = nil, rtfData: Data? = nil, imageData: Data? = nil, kind: ClipboardKind) throws -> ClipboardItem {
        let id = UUID()
        let now = Date()
        var fileName: String? = nil

        if let data = imageData {
            let processed: Data
            if retentionMode == .capped100 && data.count > 2 * 1024 * 1024 {
                processed = Self.downscaleImageData(data, maxLongEdge: 1600) ?? data
            } else {
                processed = data
            }
            fileName = "\(id.uuidString).png"
            let url = imagesDir.appendingPathComponent(fileName!)
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try processed.write(to: url, options: .atomic)
        }

        let item = ClipboardItem(id: id, createdAt: now, kind: kind, text: text, rtfData: rtfData, imageFileName: fileName, pinned: false)

        guard let db else { return item }
        do {
            try db.run(table.insert(
                colID <- id.uuidString,
                colCreatedAt <- now,
                colKind <- kind.rawValue,
                colText <- text,
                colRtfData <- rtfData,
                colImageFileName <- fileName,
                colPinned <- false
            ))
        } catch {
            if let fn = fileName { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(fn)) }
            throw error
        }

        try loadFromDB()
        try pruneIfNeeded()
        return item
    }

    func delete(id: UUID) throws {
        guard let db else { return }
        let query = table.filter(colID == id.uuidString)
        var fileName: String? = nil
        if let row = try db.pluck(query) { fileName = row[colImageFileName] }
        try db.run(query.delete())
        if let fn = fileName { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(fn)) }
        items.removeAll { $0.id == id }
    }

    func togglePin(id: UUID) throws {
        guard let db else { return }
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let newVal = !items[idx].pinned
        try db.run(table.filter(colID == id.uuidString).update(colPinned <- newVal))
        items[idx].pinned = newVal
        items.sort { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            return a.createdAt > b.createdAt
        }
    }

    func clearAll() throws {
        guard let db else { return }
        let unpinned = table.filter(colPinned == false)
        var fileNames: [String] = []
        for row in try db.prepare(unpinned) {
            if let fn = row[colImageFileName] { fileNames.append(fn) }
        }
        let pinnedCount = try db.scalar(table.filter(colPinned == true).count)
        if pinnedCount == 0 {
            try db.run(table.delete())
            for fn in fileNames { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(fn)) }
            let allFiles = (try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path)) ?? []
            for f in allFiles { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(f)) }
        } else {
            try db.run(unpinned.delete())
            for fn in fileNames { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(fn)) }
        }
        try loadFromDB()
    }

    func clearAllIncludingPinned() throws {
        guard let db else { return }
        let allFiles = (try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path)) ?? []
        try db.run(table.delete())
        for f in allFiles { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(f)) }
        items.removeAll()
    }

    @discardableResult
    func prune(mode: RetentionMode? = nil) throws -> Int {
        let m = mode ?? retentionMode
        guard let db else { return 0 }
        switch m {
        case .unlimited:
            return 0
        case .capped100:
            let count = try db.scalar(table.filter(colPinned == false).count)
            let excess = count - 100
            guard excess > 0 else { return 0 }
            let oldest = try db.prepare(table.filter(colPinned == false).order(colCreatedAt.asc).limit(excess))
            var ids: [String] = []
            var fns: [String] = []
            for row in oldest {
                ids.append(row[colID])
                if let fn = row[colImageFileName] { fns.append(fn) }
            }
            for id in ids { try db.run(table.filter(colID == id).delete()) }
            for fn in fns { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(fn)) }
            try loadFromDB()
            return ids.count
        case .last24h:
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            return try pruneOlderThan(cutoff)
        case .lastWeek:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            return try pruneOlderThan(cutoff)
        }
    }

    private func pruneOlderThan(_ cutoff: Date) throws -> Int {
        guard let db else { return 0 }
        let query = table.filter(colPinned == false && colCreatedAt < cutoff)
        var fns: [String] = []
        for row in try db.prepare(query) { if let fn = row[colImageFileName] { fns.append(fn) } }
        let count = try db.run(query.delete())
        for fn in fns { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(fn)) }
        if count > 0 { try loadFromDB() }
        return count
    }

    func pruneIfNeeded() throws { _ = try prune() }

    @discardableResult
    func cleanupOrphanImages() throws -> Int {
        let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path)) ?? []
        guard let db, !fileNames.isEmpty else { return 0 }
        var dbFileNames = Set<String>()
        for row in try db.prepare(table) { if let fn = row[colImageFileName] { dbFileNames.insert(fn) } }
        let orphans = fileNames.filter { !dbFileNames.contains($0) }
        for o in orphans { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(o)) }
        return orphans.count
    }

    static func downscaleImageData(_ data: Data, maxLongEdge: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let longEdge = max(w, h)
        guard longEdge > maxLongEdge else { return data }
        let scale = maxLongEdge / longEdge
        let newW = Int(w * scale), newH = Int(h * scale)
        guard let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(newW), height: CGFloat(newH)))
        guard let scaled = ctx.makeImage() else { return nil }
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutable as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, scaled, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutable as Data
    }
}
