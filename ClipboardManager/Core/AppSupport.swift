import Foundation

enum AppSupport {
    static var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardManager", isDirectory: true)
    }
    static var imagesURL: URL { appSupportURL.appendingPathComponent("images", isDirectory: true) }
    static var dbURL: URL { appSupportURL.appendingPathComponent("history.sqlite3") }

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
    }
}
