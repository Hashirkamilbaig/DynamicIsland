import SwiftUI

struct PlaybackProgressBar: View {
    let info: NowPlayingInfo
    var isActive: Bool
    var onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?

    private let fill = Color(red: 0.23, green: 0.51, blue: 0.98)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !(isActive && info.isPlaying) || dragFraction != nil)) { context in
            let elapsed = dragFraction.map { $0 * info.duration } ?? info.elapsed(at: context.date)
            let fraction = info.duration > 0 ? elapsed / info.duration : 0

            VStack(spacing: 4) {
                track(fraction: fraction)

                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text("–" + Self.format(max(info.duration - elapsed, 0)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func track(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(fill)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
            .frame(height: dragFraction == nil ? 4 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = min(max(value.location.x / geo.size.width, 0), 1)
                    }
                    .onEnded { _ in
                        if let dragFraction, info.duration > 0 {
                            onSeek(dragFraction * info.duration)
                        }
                        dragFraction = nil
                    }
            )
            .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
        }
        .frame(height: 12)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
