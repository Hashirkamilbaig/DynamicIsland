import XCTest
@testable import DynamicIsland

@MainActor
final class ShelfStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: ShelfStore!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIslandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ShelfStore(ttl: 0.4, cacheDirectory: tempDir)
    }

    override func tearDown() async throws {
        store.clearAll()
        try? FileManager.default.removeItem(at: tempDir)
        store = nil
        tempDir = nil
    }

    func testIngestCopiesFile() throws {
        let source = tempDir.appendingPathComponent("source.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)

        let item = store.ingest(url: source)
        XCTAssertNotNil(item)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item!.cachedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Original must remain")
        let copied = try String(contentsOf: item!.cachedURL, encoding: .utf8)
        XCTAssertEqual(copied, "hello")
    }

    func testPurgeRemovesExpiredItems() async throws {
        let source = tempDir.appendingPathComponent("expire.txt")
        try "bye".write(to: source, atomically: true, encoding: .utf8)
        let item = store.ingest(url: source)
        XCTAssertNotNil(item)

        let expectation = expectation(description: "purged")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.store.purgeExpired()
            if self.store.items.isEmpty {
                expectation.fulfill()
            }
        }
        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item!.cachedURL.path))
    }
}
