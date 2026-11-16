import SwiftUI

/// Single-line text that scrolls horizontally in a loop when it doesn't fit its width.
struct MarqueeText: View {
    let text: String
    var isActive: Bool = true

    private let gap: CGFloat = 32
    private let speed: CGFloat = 30
    private let pause: TimeInterval = 1.6
    private let fadeWidth: CGFloat = 10

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var start = Date()

    private var overflows: Bool { textWidth > containerWidth + 0.5 && containerWidth > 0 }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, width in containerWidth = width }
                }
            )
            .overlay(alignment: .leading) { scrolling }
            .clipped()
            .mask(edgeFade)
            .onChange(of: text) { _, _ in start = Date() }
            .onChange(of: isActive) { _, active in if active { start = Date() } }
    }

    private var scrolling: some View {
        TimelineView(.animation(paused: !(overflows && isActive))) { context in
            HStack(spacing: gap) {
                label
                if overflows { label }
            }
            .fixedSize()
            .offset(x: overflows && isActive ? offset(at: context.date) : 0)
        }
    }

    private var label: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { textWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, width in textWidth = width }
                }
            )
    }

    private func offset(at date: Date) -> CGFloat {
        let distance = textWidth + gap
        let scrollDuration = TimeInterval(distance / speed)
        let cycle = pause + scrollDuration
        let phase = date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
        guard phase > pause else { return 0 }
        return -CGFloat((phase - pause) / scrollDuration) * distance
    }

    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: overflows ? fadeWidth : 0)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: overflows ? fadeWidth : 0)
        }
    }
}
