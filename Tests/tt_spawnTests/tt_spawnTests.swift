import XCTest
@testable import tt_spawn

final class tt_spawnTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(tt_spawn().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
