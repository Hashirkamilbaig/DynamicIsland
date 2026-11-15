import SwiftUI

struct IslandView: View {
    @ObservedObject var state: IslandState

    private var isExpanded: Bool { state.expansion == .expanded }

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: isExpanded ? 18 : 10, y: 6)

            Group {
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    collapsedContent
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, isExpanded ? 16 : 14)
            .padding(.vertical, isExpanded ? 14 : 8)
        }
        .frame(
            width: isExpanded ? 420 : collapsedWidth,
            height: isExpanded ? 168 : 34
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: state.expansion)
        .animation(.easeOut(duration: 0.2), value: state.nowPlaying.info.title)
        .onHover { state.handleHover($0) }
        .onTapGesture { state.toggle() }
        .contentShape(Capsule())
    }

    private var collapsedWidth: CGFloat {
        if state.nowPlaying.info.hasTrack { return 220 }
        if !state.shelf.items.isEmpty { return 160 }
        return 120
    }

    private var collapsedContent: some View {
        HStack(spacing: 10) {
            if let art = state.nowPlaying.info.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Circle()
                    .fill(Color.white.opacity(state.nowPlaying.info.isPlaying ? 0.9 : 0.35))
                    .frame(width: 8, height: 8)
            }

            if state.nowPlaying.info.hasTrack {
                Text(state.nowPlaying.info.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text("Island")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if !state.shelf.items.isEmpty {
                Text("\(state.shelf.items.count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.9), in: Capsule())
            }
        }
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
