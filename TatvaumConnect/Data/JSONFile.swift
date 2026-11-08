import Foundation
import os

/// A small JSON document on disk, written atomically. Missing fields decode to defaults.
struct JSONFile<T: Codable> {
    let url: URL
    private static var log: Logger { Logger(subsystem: "com.tatvaum.connect", category: "JSONFile") }

    init(_ name: String) {
        url = URL.documentsDirectory.appending(path: name)
    }

    func read() -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { Self.log.warning("Failed to read \(url.lastPathComponent): \(error)"); return nil }
    }

    func write(_ value: T) {
        do { try JSONEncoder().encode(value).write(to: url, options: .atomic) }
        catch { Self.log.warning("Failed to write \(url.lastPathComponent): \(error)") }
    }

    func delete() { try? FileManager.default.removeItem(at: url) }
}

/// Serial background queue so successive writes land in order.
let writerQueue = DispatchQueue(label: "com.tatvaum.connect.writer", qos: .utility)
