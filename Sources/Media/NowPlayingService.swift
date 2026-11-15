import AppKit
import Combine
import Foundation

struct NowPlayingInfo: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artwork: NSImage?
    var isPlaying: Bool = false
    var bundleIdentifier: String?
    var source: Source = .none

    enum Source: String, Equatable {
        case none
        case mediaRemote
        case spotifyScript
    }

    var hasTrack: Bool {
        !title.isEmpty || !artist.isEmpty
    }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.source == rhs.source
            && (lhs.artwork == nil) == (rhs.artwork == nil)
    }
}

@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var info = NowPlayingInfo()

    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var usingFallback = false

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

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
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
        let center = DistributedNotificationCenter.default()
        let names: [Notification.Name] = [
            .mediaRemoteNowPlayingInfoDidChange,
            .mediaRemoteNowPlayingApplicationIsPlayingDidChange,
            .mediaRemoteNowPlayingApplicationDidChange
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshFromMediaRemote()
                }
            }
            observers.append(token)
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
                self.info = next
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
        if let scripted = Self.spotifyNowPlayingViaAppleScript() {
            info = scripted
        } else {
            info = NowPlayingInfo(source: .spotifyScript)
        }
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
          return t & "|||" & a & "|||" & al & "|||" & playingState
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
            isPlaying: parts[3].lowercased().contains("playing"),
            bundleIdentifier: "com.spotify.client",
            source: .spotifyScript
        )
    }
}
