import SwiftUI
import Combine

/**
 Observable model for overlay waveform intensity.
 */
@MainActor
final class WaveformViewModel: ObservableObject {
    @Published var level: CGFloat = 0
    @Published var toastMessage: String?
}

/**
 Floating waveform UI shown while recording.
 */
struct WaveformView: View {
    private let cornerRadius: CGFloat = 12

    @ObservedObject var model: WaveformViewModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(red: 0.15, green: 0.12, blue: 0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(
                                    Color(red: 0.99, green: 0.83, blue: 0.19).opacity(0.95),
                                    lineWidth: 1.2
                                )
                        )

                    HStack(alignment: .center, spacing: 4) {
                        ForEach(0..<8, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.96))
                                .frame(width: 4, height: barHeight(for: index, time: time))
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)

                if let toastMessage = model.toastMessage {
                    Text(toastMessage)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(red: 0.99, green: 0.83, blue: 0.19).opacity(0.95), lineWidth: 0.8)
                                )
                        )
                        .padding(.top, -6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.toastMessage)
        }
        .frame(width: 132, height: 52)
    }

    /**
     Computes each waveform bar height from live level and time phase.
     */
    private func barHeight(for index: Int, time: TimeInterval) -> CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 24
        let normalized = max(0, min(model.level, 1))
        let phase = sin((time * 8.0) + (Double(index) * 0.55))
        let envelope = 0.55 + (0.45 * CGFloat((phase + 1) / 2))
        return minHeight + (maxHeight - minHeight) * normalized * envelope
    }
}
