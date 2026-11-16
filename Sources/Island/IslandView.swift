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
                .offset(y: isRevealed ? 0 : IslandLayout.tuckedOffsetY)
                .opacity(isRevealed ? 1 : 0.001)
                .allowsHitTesting(isRevealed)
        }
        // Panel is always full-size; only the chrome offset animates for reveal/tuck.
        .frame(
            width: IslandLayout.panelWidth,
            height: IslandLayout.revealedPanelHeight,
            alignment: .top
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: state.presence)
        .animation(.easeOut(duration: 0.18), value: showShelf)
        .onHover { hovering in
            state.setPointerInside(hovering, reason: hovering ? "swiftui-hover" : "swiftui-hover-exit")
        }
        // Clicks do not dismiss. Drops are handled by IslandHostingView (AppKit).
    }

    private var islandChrome: some View {
        ZStack(alignment: .top) {
            // Soft outer glow / shadow against wallpaper (panel has transparent padding).
            IslandBodyShape()
                .fill(Color.black.opacity(0.45))
                .blur(radius: 18)
                .offset(y: 8)
                .padding(.horizontal, 6)

            IslandBodyShape()
                .fill(Color.black)
                .overlay(
                    IslandBodyShape()
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 22, y: 10)

            expandedContent
                .padding(.top, IslandLayout.notchClearance)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
                .opacity(isRevealed ? 1 : 0)
        }
        .frame(width: IslandLayout.islandWidth, height: IslandLayout.islandHeight)
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
            Button { PlaybackControls.previousTrack() } label: {
                Image(systemName: "backward.fill")
            }
            Button { PlaybackControls.togglePlayPause() } label: {
                Image(systemName: state.nowPlaying.info.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            Button { PlaybackControls.nextTrack() } label: {
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
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: IslandLayout.bottomCornerRadius,
            bottomTrailingRadius: IslandLayout.bottomCornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
        .path(in: rect)
    }
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
