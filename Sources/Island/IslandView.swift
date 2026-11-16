import SwiftUI
import AppKit

struct IslandView: View {
    @ObservedObject var state: IslandState
    @State private var showShelf = false
    @State private var showVolume = false

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
        .animation(.easeOut(duration: 0.18), value: showShelf)
        // Clicks do not dismiss. Drops are handled by IslandHostingView (AppKit).
    }

    private var notch: CGSize {
        NSScreen.main?.notchSize ?? CGSize(width: IslandLayout.notchHitWidth, height: IslandLayout.notchHitHeight)
    }

    private var hasNotch: Bool {
        (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
    }

    private var bodySize: CGSize {
        isRevealed ? CGSize(width: IslandLayout.islandWidth, height: IslandLayout.islandHeight) : notch
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
                .frame(width: IslandLayout.islandWidth, height: IslandLayout.islandHeight)
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
            utilityBar

            HStack(alignment: .top, spacing: 16) {
                artwork

                VStack(alignment: .leading, spacing: 6) {
                    Text(state.nowPlaying.info.hasTrack ? state.nowPlaying.info.title : "Nothing playing")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if state.nowPlaying.info.hasTrack {
                        if !state.nowPlaying.info.album.isEmpty {
                            Text(state.nowPlaying.info.album.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }

                        Text(state.nowPlaying.info.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    } else {
                        Text("Play something in Spotify or Music")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    playbackControls
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }

            if showShelf || !state.shelf.items.isEmpty {
                ShelfDropView(store: state.shelf, isExpanded: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showVolume {
                volumeRow
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var utilityBar: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { showShelf.toggle() }
            } label: {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(showShelf || !state.shelf.items.isEmpty ? .white : .white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("File shelf")

            Button {
                withAnimation(.easeOut(duration: 0.18)) { showVolume.toggle() }
            } label: {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(showVolume ? .white : .white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("System volume")

            Spacer()

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .frame(height: 16)
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
        HStack(spacing: 18) {
            Button { state.nowPlaying.previousTrack() } label: {
                Image(systemName: "backward.fill")
            }
            Button { state.nowPlaying.togglePlayPause() } label: {
                Image(systemName: state.nowPlaying.info.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            Button { state.nowPlaying.nextTrack() } label: {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
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
