import SwiftUI

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
                // Park the visible chrome up under the notch; hit strip stays put.
                .offset(y: isRevealed ? IslandLayout.revealedTopPadding : IslandLayout.tuckedOffsetY)
                .opacity(isRevealed ? 1 : 0.001)
                .allowsHitTesting(isRevealed)
        }
        .frame(
            width: IslandLayout.panelWidth,
            height: isRevealed ? IslandLayout.revealedPanelHeight : IslandLayout.notchHitHeight,
            alignment: .top
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: state.presence)
        .onHover { state.handleHover($0) }
        // Clicks do not dismiss. Drops are handled by IslandHostingView (AppKit).
    }

    private var islandChrome: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isRevealed ? 0.35 : 0), radius: 18, y: 6)

            expandedContent
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .opacity(isRevealed ? 1 : 0)
        }
        .frame(width: IslandLayout.islandWidth, height: IslandLayout.islandHeight)
        .animation(.easeOut(duration: 0.2), value: state.nowPlaying.info.title)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            mediaRow
            ShelfDropView(store: state.shelf, isExpanded: true)
            volumeRow
        }
        .foregroundStyle(.white)
    }

    private var mediaRow: some View {
        HStack(spacing: 12) {
            Group {
                if let art = state.nowPlaying.info.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(state.nowPlaying.info.hasTrack ? state.nowPlaying.info.title : "Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(state.nowPlaying.info.hasTrack ? state.nowPlaying.info.artist : "Play something in Spotify or Music")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                Button { PlaybackControls.previousTrack() } label: {
                    Image(systemName: "backward.fill")
                }
                Button { PlaybackControls.togglePlayPause() } label: {
                    Image(systemName: state.nowPlaying.info.isPlaying ? "pause.fill" : "play.fill")
                }
                Button { PlaybackControls.nextTrack() } label: {
                    Image(systemName: "forward.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
        }
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

enum IslandLayout {
    static let islandWidth: CGFloat = 420
    static let islandHeight: CGFloat = 168
    static let panelWidth: CGFloat = 420
    /// Visible island + top padding while revealed.
    static let revealedPanelHeight: CGFloat = 188
    static let revealedTopPadding: CGFloat = 6
    /// Notch sensor: wide enough for the physical notch, short so it sits in the menu-bar band.
    static let notchHitWidth: CGFloat = 320
    static let notchHitHeight: CGFloat = 28
    /// Pull chrome upward so it sits under/behind the notch when tucked.
    static let tuckedOffsetY: CGFloat = -IslandLayout.islandHeight
}
