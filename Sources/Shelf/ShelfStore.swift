import Foundation
import UniformTypeIdentifiers
import Combine

/// Ephemeral drop shelf: copies inbound files into a cache dir and purges after TTL.
@MainActor
final class ShelfStore: ObservableObject {
    nonisolated static let defaultTTL: TimeInterval = 60

    @Published private(set) var items: [ShelfItem] = []

    private let ttl: TimeInterval
    private let fileManager: FileManager
    private let cacheDirectory: URL
    private var purgeTimer: Timer?

    init(
        ttl: TimeInterval = defaultTTL,
        fileManager: FileManager = .default,
        cacheDirectory: URL? = nil
    ) {
        self.ttl = ttl
        self.fileManager = fileManager
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = base
                .appendingPathComponent("DynamicIsland", isDirectory: true)
                .appendingPathComponent("Shelf", isDirectory: true)
        }
        prepareCacheDirectory()
        startPurgeTimer()
    }

    deinit {
        // Timer is created on the main run loop; invalidate is thread-safe enough for teardown.
        purgeTimer?.invalidate()
    }

    func ingest(urls: [URL]) {
        for url in urls {
            ingest(url: url)
        }
    }

    @discardableResult
    func ingest(url: URL) -> ShelfItem? {
        prepareCacheDirectory()

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let id = UUID()
        let originalName = url.lastPathComponent
        let destination = uniqueDestination(for: originalName, id: id)

        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: url, to: destination)
            let now = Date()
            let item = ShelfItem(
                id: id,
                originalName: originalName,
                cachedURL: destination,
                createdAt: now,
                expiresAt: now.addingTimeInterval(ttl),
                contentType: UTType(filenameExtension: url.pathExtension)
            )
            items.insert(item, at: 0)
            Log.shelf.info("Ingested \(originalName, privacy: .public) expires in \(self.ttl, format: .fixed(precision: 0))s")
            return item
        } catch {
            Log.shelf.error("Failed to ingest \(originalName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func remove(_ item: ShelfItem) {
        deleteFile(at: item.cachedURL)
        items.removeAll { $0.id == item.id }
        Log.shelf.debug("Removed \(item.originalName, privacy: .public)")
    }

    func purgeExpired(now: Date = Date()) {
        let expired = items.filter { $0.expiresAt <= now }
        guard !expired.isEmpty else { return }
        for item in expired {
            deleteFile(at: item.cachedURL)
        }
        items.removeAll { $0.expiresAt <= now }
        Log.shelf.info("Purged \(expired.count) expired shelf item(s)")
    }

    func clearAll() {
        for item in items {
            deleteFile(at: item.cachedURL)
        }
        items.removeAll()
        Log.shelf.info("Cleared shelf")
    }

    // MARK: - Private

    private func prepareCacheDirectory() {
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            Log.shelf.error("Could not create cache dir: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One folder per item so the cached copy keeps its original filename,
    /// which is what Finder uses when the file is dragged back out.
    private func uniqueDestination(for name: String, id: UUID) -> URL {
        let safeName = name.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent(safeName)
    }

    private func deleteFile(at url: URL) {
        do {
            let folder = url.deletingLastPathComponent()
            let target = folder.standardizedFileURL == cacheDirectory.standardizedFileURL ? url : folder
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
        } catch {
            Log.shelf.error("Failed deleting \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startPurgeTimer() {
        purgeTimer?.invalidate()
        // Tick often enough that the TTL countdown feels accurate in the UI.
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.purgeExpired()
            }
        }
        if let purgeTimer {
            RunLoop.main.add(purgeTimer, forMode: .common)
        }
    }
}
