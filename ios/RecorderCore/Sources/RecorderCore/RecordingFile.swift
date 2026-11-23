import Foundation

/// A recording on disk. Every write goes to the OS at once (survives an app
/// crash); `syncIfDue` forces it to storage at most every 2 s (survives a
/// dead phone, losing at most the last seconds).
public final class RecordingFile {
    public enum Failure: Error { case cannotCreate(URL) }

    static let syncInterval: TimeInterval = 2

    private let handle: FileHandle
    private var lastSync: Date?

    public static func fileName(tagName: String, start: Date, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return "\(tagName.replacingOccurrences(of: " ", with: "-"))_\(f.string(from: start)).csv"
    }

    /// Creates the file and writes the header.
    public init(creating url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: Data(Rows.header.utf8)) else {
            throw Failure.cannotCreate(url)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    /// Reopens an existing recording to continue it; no second header.
    public init(appendingTo url: URL) throws {
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    public func write(_ line: String) throws {
        try handle.write(contentsOf: Data(line.utf8))
    }

    public func syncIfDue(now: Date) {
        if let lastSync, now.timeIntervalSince(lastSync) < Self.syncInterval { return }
        try? handle.synchronize()
        lastSync = now
    }

    public func close() throws {
        try handle.synchronize()
        try handle.close()
    }
}
