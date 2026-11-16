import XCTest
@testable import DynamicIsland

final class PlayModeTests: XCTestCase {
    func testCyclesOffShuffleRepeat() {
        XCTAssertEqual(PlayMode.off.next, .shuffle)
        XCTAssertEqual(PlayMode.shuffle.next, .repeatAll)
        XCTAssertEqual(PlayMode.repeatAll.next, .off)
    }

    func testDerivesModeFromSpotifyFlags() {
        XCTAssertEqual(PlayMode(shuffling: false, repeating: false), .off)
        XCTAssertEqual(PlayMode(shuffling: true, repeating: false), .shuffle)
        XCTAssertEqual(PlayMode(shuffling: false, repeating: true), .repeatAll)
        XCTAssertEqual(PlayMode(shuffling: true, repeating: true), .shuffle)
    }

    func testEachModeMapsToSingleSpotifyFlag() {
        XCTAssertFalse(PlayMode.off.shuffling || PlayMode.off.repeating)
        XCTAssertTrue(PlayMode.shuffle.shuffling && !PlayMode.shuffle.repeating)
        XCTAssertTrue(PlayMode.repeatAll.repeating && !PlayMode.repeatAll.shuffling)
    }
}
