import AppKit
import CryptoKit
import Foundation
import Network

/// Minimal Spotify Web API client (Authorization Code + PKCE, loopback redirect).
/// AppleScript can't see the playback context, so this is what tells us which
/// playlist is playing and where it ends.
@MainActor
final class SpotifyWebAPI: ObservableObject {
    static let redirectPort: UInt16 = 43821
    static let redirectURI = "http://127.0.0.1:\(redirectPort)/callback"
    private static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "playlist-read-private",
        "playlist-read-collaborative"
    ]
    private static let clientIDKey = "SpotifyClientID"

    struct Context {
        let uri: String
        let type: String
        let itemURI: String
    }

    struct ContextEnd {
        let index: Int
        let uri: String
        let durationMs: Int
    }

    enum APIError: LocalizedError {
        case notConnected
        case http(Int, String)
        case unsupportedContext(String?)
        case emptyContext

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Spotify isn't connected."
            case let .http(code, body): return "Spotify returned \(code): \(body)"
            case let .unsupportedContext(type):
                return "Play from a playlist or album first (current source: \(type ?? "none"))."
            case .emptyContext: return "That playlist is empty."
            }
        }
    }

    @Published private(set) var isConnected = false

    var clientID: String? {
        get { UserDefaults.standard.string(forKey: Self.clientIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.clientIDKey) }
    }

    private var token: StoredToken?
    private var listener: NWListener?
    private var pendingVerifier: String?
    private var pendingState: String?

    init() {
        token = StoredToken.load()
        isConnected = token != nil && clientID != nil
    }

    // MARK: - Auth

    func connect(clientID: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let verifier = Self.randomURLSafe(64)
        let state = Self.randomURLSafe(16)
        pendingVerifier = verifier
        pendingState = state

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " "))
        ]
        startCallbackListener()
        NSWorkspace.shared.open(components.url!)
    }

    func disconnect() {
        token = nil
        StoredToken.delete()
        isConnected = false
    }

    private func startCallbackListener() {
        listener?.cancel()
        guard let listener = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.redirectPort)!) else {
            Log.media.error("Spotify callback listener failed to start")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                Task { @MainActor in
                    let ok = await self?.handleCallback(request) ?? false
                    let body = ok
                        ? "Spotify connected. You can close this tab and go back to Dynamic Island."
                        : "Spotify connection failed. Close this tab and try again from the menu bar."
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func handleCallback(_ request: String) async -> Bool {
        guard let line = request.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://127.0.0.1\(path)"),
              components.path == "/callback" else { return false }
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        defer {
            listener?.cancel()
            listener = nil
        }
        guard let code = items["code"], items["state"] == pendingState, let verifier = pendingVerifier, let clientID else {
            Log.media.error("Spotify auth callback rejected: \(items["error"] ?? "state mismatch", privacy: .public)")
            return false
        }
        do {
            token = try await requestToken([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": clientID,
                "code_verifier": verifier
            ], keepingRefresh: nil)
            isConnected = true
            Log.media.info("Spotify Web API connected")
            return true
        } catch {
            Log.media.error("Spotify token exchange failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func requestToken(_ form: [String: String], keepingRefresh oldRefresh: String?) async throws -> StoredToken {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\(Self.formEscape($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw APIError.http(status, String(data: data, encoding: .utf8) ?? "") }
        struct Reply: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        let stored = StoredToken(
            accessToken: reply.access_token,
            refreshToken: reply.refresh_token ?? oldRefresh ?? "",
            expiresAt: Date().addingTimeInterval(reply.expires_in - 60)
        )
        stored.save()
        return stored
    }

    private func validAccessToken() async throws -> String {
        guard let token, let clientID else { throw APIError.notConnected }
        if token.expiresAt > Date() { return token.accessToken }
        let refreshed = try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken,
            "client_id": clientID
        ], keepingRefresh: token.refreshToken)
        self.token = refreshed
        return refreshed.accessToken
    }

    // MARK: - API

    private func call(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Data {
        var components = URLComponents(string: "https://api.spotify.com/v1\(path)")!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError.http(status, String(data: data, encoding: .utf8) ?? "") }
        return data
    }

    private func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func currentContext() async throws -> Context {
        let data = try await call("GET", "/me/player")
        let player = json(data)
        let context = player["context"] as? [String: Any]
        let type = context?["type"] as? String
        guard let uri = context?["uri"] as? String, type == "playlist" || type == "album" else {
            throw APIError.unsupportedContext(type)
        }
        let item = player["item"] as? [String: Any]
        return Context(uri: uri, type: type ?? "", itemURI: item?["uri"] as? String ?? "")
    }

    /// Last playable entry of a playlist or album.
    func end(of context: Context) async throws -> ContextEnd {
        guard let id = context.uri.split(separator: ":").last.map(String.init) else { throw APIError.emptyContext }
        let collection = context.type == "album" ? "/albums/\(id)/tracks" : "/playlists/\(id)/items"
        let legacyCollection = "/playlists/\(id)/tracks"

        func page(_ path: String, offset: Int) async throws -> [String: Any] {
            json(try await call("GET", path, query: ["limit": "1", "offset": String(offset)]))
        }

        var path = collection
        var first: [String: Any]
        do {
            first = try await page(path, offset: 0)
        } catch APIError.http(404, _) where context.type == "playlist" {
            path = legacyCollection
            first = try await page(path, offset: 0)
        }
        let total = first["total"] as? Int ?? 0
        guard total > 0 else { throw APIError.emptyContext }
        let last = try await page(path, offset: total - 1)
        let entry = (last["items"] as? [[String: Any]])?.first ?? [:]
        let track = (entry["track"] as? [String: Any]) ?? (entry["item"] as? [String: Any]) ?? entry
        return ContextEnd(
            index: total - 1,
            uri: track["uri"] as? String ?? "",
            durationMs: track["duration_ms"] as? Int ?? 0
        )
    }

    func play(context: String, index: Int, positionMs: Int) async throws {
        _ = try await call("PUT", "/me/player/play", body: [
            "context_uri": context,
            "offset": ["position": index],
            "position_ms": positionMs
        ])
    }

    // MARK: - Helpers

    private static func randomURLSafe(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Stored in Application Support with owner-only permissions; the Keychain would
/// re-prompt after every rebuild because the app is ad-hoc signed.
private struct StoredToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("spotify-token.json")
    }

    static func load() -> StoredToken? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        FileManager.default.createFile(atPath: Self.url.path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
