import AppKit
import Combine
import Foundation

struct NowPlayingInfo: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artwork: NSImage?
    var artworkURL: URL?
    var isPlaying: Bool = false
    var bundleIdentifier: String?
    var source: Source = .none
    /// Playback position in seconds as of `positionDate`.
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var positionDate = Date()
    var shuffling = false
    var repeating = false

    var playMode: PlayMode { PlayMode(shuffling: shuffling, repeating: repeating) }

    enum Source: String, Equatable {
        case none
        case mediaRemote
        case spotifyScript
    }

    var hasTrack: Bool {
        !title.isEmpty || !artist.isEmpty
    }

    func elapsed(at date: Date) -> TimeInterval {
        let live = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        return duration > 0 ? min(max(live, 0), duration) : max(live, 0)
    }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.source == rhs.source
            && lhs.artworkURL == rhs.artworkURL
            && lhs.position == rhs.position
            && lhs.duration == rhs.duration
            && lhs.shuffling == rhs.shuffling
            && lhs.repeating == rhs.repeating
            && (lhs.artwork == nil) == (rhs.artwork == nil)
    }
}

@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var info = NowPlayingInfo()

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var pollTimer: Timer?
    private var usingFallback = false
    /// Refreshes that land right after a tap can still report the old state; keep the
    /// optimistic play/pause value until the player has had time to catch up.
    private var optimisticPlayStateUntil = Date.distantPast
    private var optimisticModeUntil = Date.distantPast
    private let artworkLoader = ArtworkLoader()

    func start() {
        if MediaRemoteBridge.isAvailable {
            MediaRemoteBridge.registerForNotifications()
            installMediaRemoteObservers()
            refreshFromMediaRemote()
            Log.media.info("NowPlayingService using MediaRemote")
        } else {
            usingFallback = true
            Log.media.error("MediaRemote unavailable; falling back to Spotify AppleScript polling")
            startFallbackPolling()
        }
    }

    func togglePlayPause() {
        let now = Date()
        info.position = info.elapsed(at: now)
        info.positionDate = now
        info.isPlaying.toggle()
        optimisticPlayStateUntil = Date().addingTimeInterval(0.8)
        PlaybackControls.togglePlayPause()
        scheduleReconcile()
    }

    func cyclePlayMode() {
        let next = info.playMode.next
        info.shuffling = next.shuffling
        info.repeating = next.repeating
        optimisticModeUntil = Date().addingTimeInterval(1.5)
        PlaybackControls.setPlayMode(next)
        scheduleReconcile()
    }

    /// Restarts the current song outside its playlist so it's the last thing
    /// queued; when it ends, Spotify's Autoplay continues with new related songs.
    func playNewSongsAfterThis() {
        guard info.bundleIdentifier == "com.spotify.client", info.hasTrack else { return }
        info.shuffling = false
        info.repeating = false
        optimisticModeUntil = Date().addingTimeInterval(1.5)
        PlaybackControls.continueWithAutoplay()
        scheduleReconcile()
    }

    func seek(to seconds: TimeInterval) {
        info.position = seconds
        info.positionDate = Date()
        PlaybackControls.seek(to: seconds)
        scheduleReconcile()
    }

    func nextTrack() {
        PlaybackControls.nextTrack()
        scheduleReconcile()
    }

    func previousTrack() {
        PlaybackControls.previousTrack()
        scheduleReconcile()
    }

    private func scheduleReconcile() {
        for delay in [0.3, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
            }
        }
    }

    func stop() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        if usingFallback || !MediaRemoteBridge.isAvailable {
            refreshFromSpotifyScript()
        } else {
            refreshFromMediaRemote()
        }
    }

    // MARK: - MediaRemote

    private func installMediaRemoteObservers() {
        let names: [Notification.Name] = [
            .mediaRemoteNowPlayingInfoDidChange,
            .mediaRemoteNowPlayingApplicationIsPlayingDidChange,
            .mediaRemoteNowPlayingApplicationDidChange
        ]
        // MediaRemote posts to the in-process center after registration; keep the
        // distributed center too in case a given OS build uses it.
        let centers: [NotificationCenter] = [.default, DistributedNotificationCenter.default()]
        for center in centers {
            for name in names {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.refreshFromMediaRemote()
                    }
                }
                observers.append((center, token))
            }
        }

        // Soft poll in case some OS builds drop notifications.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromMediaRemote()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func refreshFromMediaRemote() {
        MediaRemoteBridge.fetchNowPlaying { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                var next = NowPlayingInfo(
                    title: snapshot.title ?? "",
                    artist: snapshot.artist ?? "",
                    album: snapshot.album ?? "",
                    artwork: snapshot.artwork,
                    isPlaying: snapshot.isPlaying,
                    bundleIdentifier: snapshot.bundleIdentifier,
                    source: .mediaRemote
                )
                if !next.hasTrack {
                    // Empty MR payload: try Spotify script once so local Spotify still shows.
                    if let scripted = Self.spotifyNowPlayingViaAppleScript() {
                        next = scripted
                    }
                }
                self.apply(next)
            }
        }
    }

    // MARK: - AppleScript fallback (Spotify only)

    private func startFallbackPolling() {
        refreshFromSpotifyScript()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromSpotifyScript()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func refreshFromSpotifyScript() {
        apply(Self.spotifyNowPlayingViaAppleScript() ?? NowPlayingInfo(source: .spotifyScript))
    }

    private func apply(_ next: NowPlayingInfo) {
        var next = next
        if Date() < optimisticPlayStateUntil {
            next.isPlaying = info.isPlaying
        }
        if Date() < optimisticModeUntil {
            next.shuffling = info.shuffling
            next.repeating = info.repeating
        }
        if next.artwork == nil, let url = next.artworkURL {
            if let cached = artworkLoader.cachedImage(for: url) {
                next.artwork = cached
            } else {
                artworkLoader.load(url) { [weak self] image in
                    guard let self, self.info.artworkURL == url else { return }
                    self.info.artwork = image
                }
            }
        }
        info = next
    }

    static func spotifyNowPlayingViaAppleScript() -> NowPlayingInfo? {
        let source = """
        tell application "System Events"
          set spotifyRunning to (name of processes) contains "Spotify"
        end tell
        if spotifyRunning is false then return "not-running"
        tell application "Spotify"
          if player state is stopped then return "stopped"
          set t to name of current track
          set a to artist of current track
          set al to album of current track
          set playingState to player state as string
          set art to artwork url of current track
          set pos to (player position * 1000) as integer
          set dur to duration of current track
          set shuf to shuffling as string
          set rep to repeating as string
          return t & "|||" & a & "|||" & al & "|||" & playingState & "|||" & art & "|||" & pos & "|||" & dur & "|||" & shuf & "|||" & rep
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            Log.media.error("Spotify AppleScript error: \(String(describing: error), privacy: .public)")
            return nil
        }
        let raw = result.stringValue ?? ""
        if raw == "not-running" || raw == "stopped" || raw.isEmpty {
            return nil
        }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 4 else { return nil }
        return NowPlayingInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            artwork: nil,
            artworkURL: parts.count > 4 ? URL(string: parts[4]) : nil,
            isPlaying: parts[3].lowercased().contains("playing"),
            bundleIdentifier: "com.spotify.client",
            source: .spotifyScript,
            position: parts.count > 5 ? (Double(parts[5]) ?? 0) / 1000 : 0,
            duration: parts.count > 6 ? (Double(parts[6]) ?? 0) / 1000 : 0,
            shuffling: parts.count > 7 && parts[7] == "true",
            repeating: parts.count > 8 && parts[8] == "true"
        )
    }
}
