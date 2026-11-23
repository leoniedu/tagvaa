import SwiftUI

@main
struct TagRecorderApp: App {
    // Created at launch, before any scene: a background relaunch by iOS for a
    // Bluetooth event must reconnect and keep writing with no screen shown.
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                RecordView()
                    .tabItem { Label("Gravar", systemImage: "record.circle") }
                RecordingsView()
                    .tabItem { Label("Gravações", systemImage: "list.bullet") }
            }
            .environmentObject(model)
        }
    }
}
