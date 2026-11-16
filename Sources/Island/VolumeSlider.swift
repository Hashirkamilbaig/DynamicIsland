import SwiftUI

/// Applies the volume on every drag movement; the stock macOS Slider in this
/// non-activating panel only committed its value on mouse-up.
struct VolumeSlider: View {
    let value: Float
    var onChange: (Float) -> Void

    @State private var dragValue: Float?

    private var shown: CGFloat { CGFloat(dragValue ?? value) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knob: CGFloat = dragValue == nil ? 12 : 14

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                    .frame(height: 4)
                Capsule().fill(Color.white)
                    .frame(width: max(width * shown, 0), height: 4)
                Circle().fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: min(max(width * shown - knob / 2, 0), width - knob))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let next = Float(min(max(drag.location.x / width, 0), 1))
                        dragValue = next
                        onChange(next)
                    }
                    .onEnded { _ in dragValue = nil }
            )
            .animation(.easeOut(duration: 0.12), value: dragValue == nil)
        }
        .frame(height: 18)
    }
}
