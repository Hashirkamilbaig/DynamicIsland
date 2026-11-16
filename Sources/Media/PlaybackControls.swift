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

    static func setPlayMode(_ mode: PlayMode) {
        runSpotifyCommandAsync("""
          set shuffling to \(mode.shuffling)
          set repeating to \(mode.repeating)
        """)
    }

    static func continueWithAutoplay() {
        runSpotifyCommandAsync("""
          set shuffling to false
          set repeating to false
          set trackID to id of current track
          set resumeAt to player position
          set wasPlaying to (player state is playing)
          play track trackID
          delay 0.3
          set player position to resumeAt
          if not wasPlaying then pause
        """)
    }

    /// Scripts that `delay` must stay off the main thread.
    private static func runSpotifyCommandAsync(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            runSpotifyCommand(command)
        }
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
