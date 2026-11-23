import SwiftUI

struct RecordingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.recordings.isEmpty {
                    Text("Nenhuma gravação ainda.").foregroundStyle(.secondary)
                }
                ForEach(model.recordings, id: \.self) { url in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(url.lastPathComponent).font(.callout)
                            Text(size(url)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                    .swipeActions {
                        if url != model.recorder.activeSession?.fileURL {
                            Button("Apagar", role: .destructive) { model.delete(url) }
                        }
                    }
                }
            }
            .navigationTitle("Gravações")
            .onAppear { model.refreshRecordings() }
        }
    }

    private func size(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
