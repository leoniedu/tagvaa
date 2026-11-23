import SwiftUI

/// Stops only after a 2 s press, so a bump through the dry bag cannot end a
/// session. A short tap shows how to stop.
struct HoldToStopButton: View {
    let action: () -> Void
    private let holdSeconds = 2.0
    @State private var progress = 0.0
    @State private var showHint = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 8)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 34, height: 34)
            }
            .frame(width: 96, height: 96)
            .contentShape(Circle())
            .onTapGesture { showHint = true }
            .onLongPressGesture(minimumDuration: holdSeconds, maximumDistance: 40) {
                progress = 0
                action()
            } onPressingChanged: { pressing in
                if pressing {
                    showHint = false
                    withAnimation(.linear(duration: holdSeconds)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }
            .accessibilityLabel("Parar gravação")
            .accessibilityHint("Segure por 2 segundos")
            .accessibilityAction { action() }
            Text(showHint ? "Segure para parar" : "Segure 2 s para parar")
                .font(.footnote)
                .foregroundStyle(showHint ? .red : .secondary)
        }
    }
}
