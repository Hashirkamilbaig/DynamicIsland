import AppKit
import Foundation

/// Thin boundary around Apple's private MediaRemote framework.
/// Keep all private-API symbols here so the rest of the app stays readable.
enum MediaRemoteBridge {
    struct NowPlayingSnapshot: Sendable {
        var title: String?
        var artist: String?
        var album: String?
        var artwork: NSImage?
        var isPlaying: Bool
        var bundleIdentifier: String?
    }

    enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
        case stop = 6
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    private static let handle: UnsafeMutableRawPointer? = {
        dlopen(frameworkPath, RTLD_LAZY)
    }()

    static var isAvailable: Bool {
        handle != nil
    }

    // Function pointer types matching MediaRemote C APIs.
    private typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias RegisterNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle else { return nil }
        guard let sym = dlsym(handle, name) else {
            Log.media.error("MediaRemote symbol missing: \(name, privacy: .public)")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }

    static func registerForNotifications(queue: DispatchQueue = .main) {
        guard let register: RegisterNotificationsFn = symbol("MRMediaRemoteRegisterForNowPlayingNotifications") else {
            Log.media.error("Cannot register Now Playing notifications")
            return
        }
        register(queue)
        Log.media.info("Registered for MediaRemote Now Playing notifications")
    }

    static func fetchNowPlaying(completion: @escaping (NowPlayingSnapshot) -> Void) {
        guard let getInfo: GetNowPlayingInfoFn = symbol("MRMediaRemoteGetNowPlayingInfo") else {
            completion(NowPlayingSnapshot(isPlaying: false))
            return
        }
        let getPlaying: GetIsPlayingFn? = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying")

        getInfo(DispatchQueue.main) { info in
            var snapshot = NowPlayingSnapshot(
                title: info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
                album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String,
                artwork: nil,
                isPlaying: false,
                bundleIdentifier: info["kMRMediaRemoteNowPlayingInfoApplicationBundleIdentifier"] as? String
                    ?? Bundle.main.object(forInfoDictionaryKey: "NSAppleMusicUsageDescription") as? String
            )

            if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                snapshot.artwork = NSImage(data: data)
            }

            // Bundle id sometimes arrives via a separate notification userInfo; keep optional.
            if snapshot.bundleIdentifier == nil,
               let appInfo = info["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] {
                _ = appInfo
            }

            if let getPlaying {
                getPlaying(DispatchQueue.main) { playing in
                    snapshot.isPlaying = playing
                    completion(snapshot)
                }
            } else {
                let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
                snapshot.isPlaying = rate > 0
                completion(snapshot)
            }
        }
    }

    @discardableResult
    static func send(_ command: Command) -> Bool {
        guard let send: SendCommandFn = symbol("MRMediaRemoteSendCommand") else {
            Log.media.error("MRMediaRemoteSendCommand unavailable")
            return false
        }
        let ok = send(command.rawValue, nil)
        Log.media.debug("Send command \(command.rawValue) -> \(ok)")
        return ok
    }
}

// Notification names posted by MediaRemote (stringly typed private API).
extension Notification.Name {
    static let mediaRemoteNowPlayingInfoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let mediaRemoteNowPlayingApplicationIsPlayingDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
    static let mediaRemoteNowPlayingApplicationDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification")
}
