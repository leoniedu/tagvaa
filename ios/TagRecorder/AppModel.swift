import Foundation
import RecorderCore

/// Owns the recorder and its Bluetooth and GPS sources for the whole process,
/// so a background relaunch by iOS (Bluetooth state restoration) finds them
/// without any screen being shown.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    struct Nearby: Identifiable, Equatable {
        let tag: TagInfo
        var rssi: Int
        var id: UUID { tag.peripheralID }
    }

    @Published private(set) var nearby: [Nearby] = []
    @Published var selected: TagInfo?
    @Published private(set) var recordings: [URL] = []

    let recorder: Recorder
    private let link = BLETagLink()
    private let gps = PhoneGPS()
    private let store: SessionStore
    let directory: URL

    private init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        store = SessionStore(directory: directory)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        recorder = Recorder(link: link, directory: directory, appVersion: version)
        selected = store.lastTag
        recorder.onChange = { [weak self] in self?.recorderChanged() }
        gps.onFix = { [weak self] fix in self?.recorder.add(fix) }
        if let session = store.activeSession {
            if session.isResumable(now: Date()) {
                recorder.resume(tag: session.tag, fileURL: session.fileURL, startedAt: session.startedAt)
                gps.start()
            } else {
                store.activeSession = nil   // cut short long ago (dead phone): never append to it
            }
        }
        refreshRecordings()
    }

    var isRecording: Bool {
        [.connecting, .recording, .reconnecting].contains(recorder.state)
    }

    func startScanning() {
        link.scan { [weak self] tag, rssi in
            guard let self else { return }
            if let i = nearby.firstIndex(where: { $0.id == tag.peripheralID }) {
                nearby[i].rssi = rssi
            } else {
                nearby.append(Nearby(tag: tag, rssi: rssi))
                nearby.sort { $0.tag.name < $1.tag.name }
            }
        }
    }

    func stopScanning() {
        link.stopScan()
    }

    func startRecording() {
        guard let tag = selected, !isRecording else { return }
        store.lastTag = tag
        stopScanning()
        recorder.start(tag: tag)
        guard isRecording else { return }
        store.activeSession = recorder.activeSession
        gps.start()
        refreshRecordings()
    }

    func stopRecording() {
        recorder.stop()
    }

    func delete(_ url: URL) {
        if let session = recorder.activeSession, session.refersTo(url) { return }
        try? FileManager.default.removeItem(at: url)
        refreshRecordings()
    }

    private var lastState: RecorderState = .idle
    private var lastRefresh = Date.distantPast

    /// Called on every packet; the screen only needs a refresh twice a second.
    private func recorderChanged() {
        let stateChanged = recorder.state != lastState
        lastState = recorder.state
        if stateChanged && !isRecording {
            store.activeSession = nil
            gps.stop()
            refreshRecordings()
        }
        let now = Date()
        if stateChanged || now.timeIntervalSince(lastRefresh) >= 0.5 {
            lastRefresh = now
            objectWillChange.send()
        }
    }

    func refreshRecordings() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        recordings = urls.filter { $0.pathExtension == "csv" }.sorted { modified($0) > modified($1) }
    }
}
