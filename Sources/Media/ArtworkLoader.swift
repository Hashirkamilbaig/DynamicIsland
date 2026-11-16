import AppKit

/// Downloads and caches cover art by URL (Spotify exposes an https artwork URL, not image data).
@MainActor
final class ArtworkLoader {
    private var cache: [URL: NSImage] = [:]
    private var inFlight: Set<URL> = []

    func cachedImage(for url: URL) -> NSImage? {
        cache[url]
    }

    func load(_ url: URL, completion: @escaping (NSImage) -> Void) {
        if let image = cache[url] {
            completion(image)
            return
        }
        guard inFlight.insert(url).inserted else { return }

        Task {
            defer { inFlight.remove(url) }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = NSImage(data: data) else { return }
                // Only a handful of tracks matter; keep the cache from growing unbounded.
                if cache.count > 20 { cache.removeAll() }
                cache[url] = image
                completion(image)
            } catch {
                Log.media.error("Artwork download failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
