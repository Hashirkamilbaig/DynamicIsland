import SwiftUI
import AppKit

struct IslandView: View {
    @ObservedObject var state: IslandState

    private var isRevealed: Bool { state.isRevealed }

    var body: some View {
        ZStack(alignment: .top) {
            // Invisible notch hit strip so hover/drag still work while tucked.
            Color.clear
                .frame(width: IslandLayout.notchHitWidth, height: IslandLayout.notchHitHeight)
                .contentShape(Rectangle())

            islandChrome
                .allowsHitTesting(isRevealed)
        }
        // Panel is always full-size; only the chrome morphs between notch size and full size.
        // Do NOT attach .onHover here — it tracks the full panel frame and made the
        // tucked hot zone feel island-sized. Reveal is driven only by the mouse monitor
        // + AppKit hitTest against the measured notch (NSScreen.notchSize).
        .frame(
            width: IslandLayout.panelWidth,
            height: IslandLayout.revealedPanelHeight,
            alignment: .top
        )
        .animation(isRevealed ? IslandMotion.grow : IslandMotion.shrink, value: state.presence)
        .animation(IslandMotion.grow, value: state.showVolume)
        // Clicks do not dismiss. Drops are handled by IslandHostingView (AppKit).
    }

    private var notch: CGSize {
        NSScreen.main?.notchSize ?? CGSize(width: IslandLayout.notchHitWidth, height: IslandLayout.notchHitHeight)
    }

    private var hasNotch: Bool {
        (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
    }

    private var bodySize: CGSize {
        isRevealed ? CGSize(width: IslandLayout.islandWidth, height: state.bodyHeight) : notch
    }

    private var islandChrome: some View {
        ZStack(alignment: .top) {
            // Body grows out of the notch and shrinks back into it. When tucked it is exactly
            // notch-sized and black, so it hides behind the hardware notch.
            IslandBodyShape(bottomRadius: isRevealed ? IslandLayout.bottomCornerRadius : IslandLayout.notchCornerRadius)
                .fill(Color.black)
                .frame(width: bodySize.width, height: bodySize.height)
                .shadow(color: .black.opacity(isRevealed ? 0.25 : 0), radius: 14, y: 6)
            .opacity(isRevealed || hasNotch ? 1 : 0)

            expandedContent
                .padding(.top, IslandLayout.notchClearance)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
                .frame(width: IslandLayout.islandWidth, height: state.bodyHeight)
                .scaleEffect(isRevealed ? 1 : 0.4, anchor: .top)
                .blur(radius: isRevealed ? 0 : 6)
                .opacity(isRevealed ? 1 : 0)
                .animation(isRevealed ? IslandMotion.contentIn : IslandMotion.contentOut, value: state.presence)
        }
        .frame(width: IslandLayout.islandWidth, height: IslandLayout.islandHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: state.nowPlaying.info.title)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                artwork

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        MarqueeText(text: info.hasTrack ? info.title : "Nothing playing", isActive: isRevealed)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                        volumeToggle
                    }

                    MarqueeText(text: subtitle, isActive: isRevealed)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))

                    playbackControls
                        .padding(.top, 2)

                    PlaybackProgressBar(info: info, isActive: isRevealed) { state.nowPlaying.seek(to: $0) }
                        .opacity(info.duration > 0 ? 1 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ShelfDropView(store: state.shelf)
                    .frame(width: IslandLayout.shelfWidth, height: IslandLayout.artSize)
            }

            if state.showVolume {
                volumeRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var info: NowPlayingInfo { state.nowPlaying.info }

    private var subtitle: String {
        guard info.hasTrack else { return "Play something in Spotify or Music" }
        return [info.artist, info.album].filter { !$0.isEmpty }.joined(separator: " – ")
    }

    private var volumeToggle: some View {
        Button {
            state.showVolume.toggle()
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(state.showVolume ? 0.9 : 0.4))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("System volume")
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let art = state.nowPlaying.info.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                        )
                }
            }
            .frame(width: IslandLayout.artSize, height: IslandLayout.artSize)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            sourceBadge
                .offset(x: 4, y: 4)
        }
    }

    private var sourceBadge: some View {
        Group {
            if let badge = SourceBadge.style(for: state.nowPlaying.info.bundleIdentifier) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(badge.color)
                    Image(systemName: badge.symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 0) {
            transportButton("backward.fill", size: 18) { state.nowPlaying.previousTrack() }
            Spacer(minLength: 0)
            transportButton(info.isPlaying ? "pause.fill" : "play.fill", size: 24) {
                state.nowPlaying.togglePlayPause()
            }
            Spacer(minLength: 0)
            transportButton("forward.fill", size: 18) { state.nowPlaying.nextTrack() }
        }
        .padding(.horizontal, -8)
        .foregroundStyle(.white.opacity(0.75))
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(TransportButtonStyle())
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Button {
                state.volume.toggleMute()
            } label: {
                Image(systemName: state.volume.isMuted || state.volume.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { Double(state.volume.isMuted ? 0 : state.volume.volume) },
                    set: { state.volume.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .tint(.white)

            Text("\(Int((state.volume.isMuted ? 0 : state.volume.volume) * 100))%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 34, alignment: .trailing)
        }
    }
}

/// Flat against the top of the screen; heavily rounded only at the bottom so it
/// visually merges with the hardware notch instead of reading as a floating pill.
struct IslandBodyShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        return UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: 0,
            style: .continuous
        )
        .path(in: rect)
    }
}

private enum IslandMotion {
    /// Slight overshoot as it pops out of the notch.
    static let grow = Animation.spring(response: 0.42, dampingFraction: 0.74)
    /// Quicker, no bounce, so it reads as being sucked back in.
    static let shrink = Animation.spring(response: 0.3, dampingFraction: 0.95)
    /// Content appears once the body has started opening.
    static let contentIn = Animation.easeOut(duration: 0.22).delay(0.1)
    /// Content vanishes before the body closes around it.
    static let contentOut = Animation.easeIn(duration: 0.1)
}

private enum SourceBadge {
    struct Style {
        let symbol: String
        let color: Color
    }

    static func style(for bundleID: String?) -> Style? {
        guard let bundleID else { return nil }
        let id = bundleID.lowercased()
        if id.contains("spotify") {
            return Style(symbol: "music.note.list", color: Color(red: 0.11, green: 0.73, blue: 0.33))
        }
        if id.contains("music") || id.contains("itunes") {
            return Style(symbol: "music.note", color: Color(red: 0.94, green: 0.20, blue: 0.35))
        }
        if id.contains("chrome") || id.contains("safari") || id.contains("firefox") || id.contains("browser") {
            return Style(symbol: "globe", color: Color(red: 0.20, green: 0.48, blue: 0.96))
        }
        return Style(symbol: "waveform", color: Color.white.opacity(0.35))
    }
}

private struct TransportButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.22 : isHovering ? 0.12 : 0))
                    .frame(width: 34, height: 34)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}
