import XCTest
@testable import WebSocket

class WebSocketTests: XCTestCase {
    func testReality() {
        XCTAssert(2 + 2 == 4, "Something is severely wrong here.")
    }
}

extension WebSocketTests {
    static var allTests: [(String, WebSocketTests -> () throws -> Void)] {
        return [
           ("testReality", testReality),
        ]
    }
}
