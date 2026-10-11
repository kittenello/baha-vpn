import XCTest
@testable import BahaCore

final class DeviceHeadersTests: XCTestCase {
    let url = URL(string: "https://example.com/sub")!
    func testDeviceHeadersOnEverySubscriptionRequest() throws {
        let device = SubscriptionDevice(hwid: String(repeating: "a", count: 64), os: "iOS", version: "18.0", model: "iPhone")
        let request = try SubscriptionLoader.makeRequest(url, device: device)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-hwid"), device.hwid)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-device-os"), "iOS")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-ver-os"), "18.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-device-model"), "iPhone")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "baha-vpn/0.1.0")
    }
    func testInvalidDeviceIdentifierRejected() {
        let invalid = SubscriptionDevice(hwid: "bad!", os: "iOS", version: "18", model: "iPhone")
        XCTAssertThrowsError(try SubscriptionLoader.makeRequest(url, device: invalid))
    }
    func testLimitWithHTTP200StillFailsClearly() {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["x-hwid-max-devices-reached": "true"])!
        XCTAssertThrowsError(try SubscriptionResponsePolicy.check(response)) { error in
            XCTAssertTrue(error.localizedDescription.contains("лимит устройств"))
        }
    }
    func testMissingHWIDWith404GetsSpecificError() {
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil,
                                       headerFields: ["x-hwid-not-supported": "true"])!
        XCTAssertThrowsError(try SubscriptionResponsePolicy.check(response)) { error in
            XCTAssertTrue(error.localizedDescription.contains("идентификатор устройства"))
        }
    }
    func testNormalResponseAndLegacyLimit() throws {
        try SubscriptionResponsePolicy.check(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        XCTAssertThrowsError(try SubscriptionResponsePolicy.check(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["x-hwid-limit": "true"])!))
    }
}
