#if os(Linux)

import XCTest
@testable import WebSocketTestSuite

XCTMain([
    testCase(WebSocketTests.allTests)
])

#endif
