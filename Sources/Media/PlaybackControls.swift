import Foundation

enum PlaybackControls {
    static func togglePlayPause() {
        if MediaRemoteBridge.isAvailable {
            _ = MediaRemoteBridge.send(.togglePlayPause)
            return
        }
        runSpotifyCommand("playpause")
    }

    static func nextTrack() {
        if MediaRemoteBridge.isAvailable {
            _ = MediaRemoteBridge.send(.nextTrack)
            return
        }
        runSpotifyCommand("next track")
    }

    static func previousTrack() {
        if MediaRemoteBridge.isAvailable {
            _ = MediaRemoteBridge.send(.previousTrack)
            return
        }
        runSpotifyCommand("previous track")
    }

    /// MediaRemote has no seek command in the bridge, so seeking is Spotify-only.
    static func seek(to seconds: TimeInterval) {
        runSpotifyCommand("set player position to \(Int(seconds.rounded()))")
    }

    private static func runSpotifyCommand(_ command: String) {
        let source = """
        tell application "Spotify"
          \(command)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.media.error("Spotify control failed: \(String(describing: error), privacy: .public)")
        }
    }
}
