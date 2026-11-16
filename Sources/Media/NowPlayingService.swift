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
    /// `spotify:track:…` when known.
    var trackID = ""

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
            && lhs.trackID == rhs.trackID
            && (lhs.artwork == nil) == (rhs.artwork == nil)
    }
}

@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var info = NowPlayingInfo()
    /// "New songs after this" is waiting for the current song to finish.
    @Published private(set) var newSongsArmed = false

    let spotifyAPI = SpotifyWebAPI()
    var onNeedsSpotifyConnection: (() -> Void)?
    var onError: ((String) -> Void)?

    private struct Handoff {
        let trackID: String
        let contextURI: String
        let end: SpotifyWebAPI.ContextEnd
    }
    private var handoff: Handoff?
    private var handoffWork: DispatchWorkItem?
    private var armedTrackID = ""
    private var lastRemaining: TimeInterval = .infinity

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

    /// Lets the current song finish, then jumps to the very end of the playlist
    /// (or album) it's playing from. Reaching the end of the context is what makes
    /// Spotify's Autoplay recommend songs based on that playlist.
    func playNewSongsAfterThis() {
        guard info.bundleIdentifier == "com.spotify.client", info.hasTrack else { return }
        if newSongsArmed {
            cancelNewSongs(reason: "toggled off")
            return
        }
        guard spotifyAPI.isConnected else {
            onNeedsSpotifyConnection?()
            return
        }
        newSongsArmed = true
        armedTrackID = info.trackID
        Task {
            do {
                let context = try await spotifyAPI.currentContext()
                let end = try await spotifyAPI.end(of: context)
                guard newSongsArmed, armedTrackID == info.trackID else { return }
                info.shuffling = false
                info.repeating = false
                optimisticModeUntil = Date().addingTimeInterval(1.5)
                PlaybackControls.setPlayMode(.off)
                if end.uri == info.trackID {
                    // Already the last song; Autoplay takes over on its own.
                    Log.media.info("New songs: current track is already last in context")
                } else {
                    handoff = Handoff(trackID: info.trackID, contextURI: context.uri, end: end)
                    Log.media.info("New songs armed: jump to \(context.uri, privacy: .public) #\(end.index) after current track")
                }
                scheduleHandoff()
            } catch {
                cancelNewSongs(reason: error.localizedDescription)
                onError?(error.localizedDescription)
            }
        }
    }

    private func cancelNewSongs(reason: String) {
        handoffWork?.cancel()
        handoffWork = nil
        handoff = nil
        newSongsArmed = false
        armedTrackID = ""
        Log.media.info("New songs disarmed: \(reason, privacy: .public)")
    }

    private func scheduleHandoff() {
        handoffWork?.cancel()
        handoffWork = nil
        guard handoff != nil, info.isPlaying, info.duration > 0 else { return }
        let remaining = info.duration - info.elapsed(at: Date())
        lastRemaining = remaining
        let work = DispatchWorkItem { [weak self] in self?.fireHandoff() }
        handoffWork = work
        // Land just before the song ends so Spotify never starts the next playlist track.
        DispatchQueue.main.asyncAfter(deadline: .now() + max(remaining - 0.45, 0), execute: work)
    }

    private func fireHandoff() {
        guard let handoff else { return }
        self.handoff = nil
        handoffWork = nil
        let startAt = max(handoff.end.durationMs - 1000, 0)
        Task {
            do {
                try await spotifyAPI.play(context: handoff.contextURI, index: handoff.end.index, positionMs: startAt)
                Log.media.info("New songs: jumped to end of context")
            } catch {
                cancelNewSongs(reason: error.localizedDescription)
                onError?(error.localizedDescription)
            }
            scheduleReconcile()
        }
    }

    /// Called after every poll while armed.
    private func updateNewSongs() {
        guard newSongsArmed else { return }
        if info.trackID == armedTrackID {
            scheduleHandoff()
            return
        }
        if handoff != nil, lastRemaining < 2.5 {
            // The song ended before the timer fired; jump now.
            fireHandoff()
        }
        if handoff == nil {
            newSongsArmed = false
            armedTrackID = ""
        } else {
            cancelNewSongs(reason: "track changed before the song finished")
        }
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
        updateNewSongs()
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
          set tid to id of current track
          return t & "|||" & a & "|||" & al & "|||" & playingState & "|||" & art & "|||" & pos & "|||" & dur & "|||" & shuf & "|||" & rep & "|||" & tid
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
            repeating: parts.count > 8 && parts[8] == "true",
            trackID: parts.count > 9 ? parts[9] : ""
        )
    }
}
