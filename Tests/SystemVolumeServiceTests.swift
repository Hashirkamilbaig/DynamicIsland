import XCTest
@testable import DynamicIsland

final class SystemVolumeServiceTests: XCTestCase {
    func testClampBounds() {
        XCTAssertEqual(SystemVolumeService.clamp(-1), 0)
        XCTAssertEqual(SystemVolumeService.clamp(0), 0)
        XCTAssertEqual(SystemVolumeService.clamp(0.5), 0.5)
        XCTAssertEqual(SystemVolumeService.clamp(1), 1)
        XCTAssertEqual(SystemVolumeService.clamp(2), 1)
    }
}
