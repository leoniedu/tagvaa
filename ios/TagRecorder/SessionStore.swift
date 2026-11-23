import Foundation
import RecorderCore

/// What must survive the app being killed: the recording in progress and the
/// last Tag used. Files are kept by name, since the app container's path can
/// change between launches.
struct SessionStore {
    private struct Saved: Codable {
        let tag: TagInfo
        let fileName: String
        let startedAt: Date
    }

    private let defaults = UserDefaults.standard
    let directory: URL

    var activeSession: ActiveSession? {
        get {
            guard let data = defaults.data(forKey: "activeSession"),
                  let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
            return ActiveSession(tag: saved.tag, fileURL: directory.appendingPathComponent(saved.fileName),
                                 startedAt: saved.startedAt)
        }
        nonmutating set {
            guard let s = newValue else { return defaults.removeObject(forKey: "activeSession") }
            let saved = Saved(tag: s.tag, fileName: s.fileURL.lastPathComponent, startedAt: s.startedAt)
            defaults.set(try? JSONEncoder().encode(saved), forKey: "activeSession")
        }
    }

    var lastTag: TagInfo? {
        get { defaults.data(forKey: "lastTag").flatMap { try? JSONDecoder().decode(TagInfo.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "lastTag") }
    }
}
