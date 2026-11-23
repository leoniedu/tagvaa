import Foundation

public enum RecorderState: Equatable {
    case idle, connecting, recording, reconnecting
    case failed(String)
}

/// What the app persists so a relaunch can continue the same file.
public struct ActiveSession: Codable, Equatable {
    public let tag: TagInfo
    public let fileURL: URL
    public let startedAt: Date

    public init(tag: TagInfo, fileURL: URL, startedAt: Date) {
        (self.tag, self.fileURL, self.startedAt) = (tag, fileURL, startedAt)
    }

    /// Longest session a relaunch may continue. Longer than any outing
    /// (a race ran 158 min); a session older than this was cut short by a
    /// dead phone and must not swallow a later one.
    public static let maxResumeAge: TimeInterval = 6 * 3600

    public func isResumable(now: Date) -> Bool {
        let age = now.timeIntervalSince(startedAt)
        return age >= 0 && age <= Self.maxResumeAge
    }

    /// Whether `url` is this session's file, however its directory was
    /// spelled (listings give /private/var for /var). All recordings live in
    /// one folder and names carry the start time, so the name decides.
    public func refersTo(_ url: URL) -> Bool {
        url.lastPathComponent == fileURL.lastPathComponent
    }
}

/// One recording: writes every packet as it arrives, survives link drops and
/// app relaunches, and never needs an export step. Not thread-safe: call it
/// from one queue (the app uses the main queue).
public final class Recorder: TagLinkDelegate {
    public private(set) var state: RecorderState = .idle { didSet { onChange?() } }
    public private(set) var stats = StreamStats()
    public private(set) var fileURL: URL?
    public private(set) var startedAt: Date?
    public private(set) var activeSession: ActiveSession?
    public var onChange: (() -> Void)?

    private let link: TagLink
    private let directory: URL
    private let now: () -> Date
    private let tz: TimeZone
    private let appVersion: String
    private var file: RecordingFile?

    public init(link: TagLink, directory: URL, now: @escaping () -> Date = Date.init,
                tz: TimeZone = .current, appVersion: String) {
        self.link = link
        self.directory = directory
        self.now = now
        self.tz = tz
        self.appVersion = appVersion
        link.delegate = self
    }

    private var isOpen: Bool {
        [.connecting, .recording, .reconnecting].contains(state)
    }

    public func start(tag: TagInfo) {
        let start = now()
        let url = directory.appendingPathComponent(RecordingFile.fileName(tagName: tag.name, start: start, tz: tz))
        do {
            file = try RecordingFile(creating: url)
        } catch {
            state = .failed("não foi possível criar \(url.lastPathComponent)")
            return
        }
        stats = StreamStats()
        fileURL = url
        startedAt = start
        activeSession = ActiveSession(tag: tag, fileURL: url, startedAt: start)
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = tz
        day.dateFormat = "yyyy-MM-dd"
        state = .connecting
        writeInfo("start date=\(day.string(from: start)) tz=\(tz.identifier) app=\(appVersion) "
            + "tag=\(tag.name) peripheral=\(tag.peripheralID.uuidString)")
        if isOpen { link.connect(peripheralID: tag.peripheralID) }
    }

    public func resume(tag: TagInfo, fileURL url: URL, startedAt start: Date) {
        do {
            file = try RecordingFile(appendingTo: url)
        } catch {
            state = .failed("não foi possível reabrir \(url.lastPathComponent)")
            return
        }
        fileURL = url
        startedAt = start
        activeSession = ActiveSession(tag: tag, fileURL: url, startedAt: start)
        state = .connecting
        writeInfo("resumed")
        if isOpen { link.connect(peripheralID: tag.peripheralID) }
    }

    public func stop() {
        guard isOpen else { return }
        writeInfo("stop")
        try? file?.close()
        file = nil
        activeSession = nil
        state = .idle
        link.disconnect()
    }

    public func add(_ fix: GPSFix) {
        guard isOpen else { return }
        write(Rows.gps(fix, at: now(), tz: tz))
    }

    // MARK: TagLinkDelegate

    public func linkConnected() {
        switch state {
        case .connecting: state = .recording
        case .reconnecting:
            writeInfo("link-restored")
            if isOpen { state = .recording }
        default: break
        }
    }

    public func linkReceived(_ data: Data) {
        guard isOpen else { return }
        let text = String(decoding: data, as: UTF8.self)
        write(Rows.rx(text, at: now(), tz: tz))
        guard isOpen else { return }
        stats.ingest(text)
        file?.syncIfDue(now: now())
        onChange?()
    }

    public func linkDropped() {
        guard isOpen, let tag = activeSession?.tag else { return }
        if state != .reconnecting {
            writeInfo("link-lost")
            guard isOpen else { return }
            state = .reconnecting
        }
        // Also when a reconnect attempt itself failed: CoreBluetooth does not
        // retry on its own, and giving up would end the recording silently.
        link.connect(peripheralID: tag.peripheralID)
    }

    // MARK: Writing

    private func writeInfo(_ text: String) {
        write(Rows.info(text, at: now(), tz: tz))
    }

    private func write(_ line: String) {
        guard let file else { return }
        do {
            try file.write(line)
        } catch {
            try? file.close()
            self.file = nil
            activeSession = nil
            state = .failed("erro ao gravar: \(error.localizedDescription)")
            link.disconnect()
        }
    }
}
