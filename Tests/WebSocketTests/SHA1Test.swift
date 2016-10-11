import XCTest
@testable import WebSocket

class SHA1Test: XCTestCase {

    func testSHA1() {
        let data = Array("sha1".utf8)
        let hash = sha1(data)
        
        var hexString = ""
        for byte in hash {
            hexString += String(format: "%02x", UInt(byte))
        }
        
        XCTAssert(hexString == "415ab40ae9b7cc4e66d6769cb2c08106e8293b48")
    }

}
