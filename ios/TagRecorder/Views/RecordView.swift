import RecorderCore
import SwiftUI

struct RecordView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isRecording {
                    RecordingStatus()
                } else {
                    TagPicker()
                }
            }
            .navigationTitle("tagvaa")
        }
    }
}

private struct TagPicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if case .failed(let message) = model.recorder.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding()
            }
            List {
                Section("Tags por perto") {
                    if tags.isEmpty {
                        Text("Procurando… ligue o Tag e aproxime o telefone.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tags, id: \.tag.peripheralID) { item in
                        Button {
                            model.selected = item.tag
                        } label: {
                            HStack {
                                Image(systemName: model.selected == item.tag ? "checkmark.circle.fill" : "circle")
                                Text(item.tag.name)
                                Spacer()
                                if let rssi = item.rssi {
                                    Text("\(rssi) dBm").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            Button {
                model.startRecording()
            } label: {
                Label("Gravar", systemImage: "record.circle")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.selected == nil)
            .padding()
        }
        .onAppear { model.startScanning() }
        .onDisappear { model.stopScanning() }
    }

    /// Nearby Tags, plus the last one used even if it is not heard yet.
    private var tags: [(tag: TagInfo, rssi: Int?)] {
        var list = model.nearby.map { (tag: $0.tag, rssi: Optional($0.rssi)) }
        if let last = model.selected, !list.contains(where: { $0.tag == last }) {
            list.insert((tag: last, rssi: nil), at: 0)
        }
        return list
    }
}

private struct RecordingStatus: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let r = model.recorder
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(r.activeSession?.tag.name ?? "").font(.title2.bold())
                Label(stateText(r.state), systemImage: stateIcon(r.state))
                    .foregroundStyle(r.state == .recording ? .green : .orange)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Tempo: \(elapsed(since: r.startedAt, now: context.date))")
                }
                Text("Amostras: \(r.stats.samples)   perdidas: \(r.stats.lostSamples)")
                Text("Bateria do Tag: \(battery(r.stats.batteryMV))")
                if let url = r.fileURL {
                    Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.body.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            Text("Pode bloquear o telefone e guardá-lo: a gravação continua.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            HoldToStopButton { model.stopRecording() }
        }
        .padding()
    }

    private func stateText(_ s: RecorderState) -> String {
        switch s {
        case .connecting: return "Conectando ao Tag…"
        case .recording: return "Gravando"
        case .reconnecting: return "Sinal perdido, reconectando…"
        case .idle: return "Parado"
        case .failed(let m): return "Erro: \(m)"
        }
    }

    private func stateIcon(_ s: RecorderState) -> String {
        s == .recording ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
    }

    private func elapsed(since start: Date?, now: Date) -> String {
        guard let start else { return "–" }
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    private func battery(_ mv: Int?) -> String {
        guard let mv else { return "–" }
        return String(format: "%.2f V", Double(mv) / 1000)
    }
}
