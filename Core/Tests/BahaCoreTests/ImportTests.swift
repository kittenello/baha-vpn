import XCTest
@testable import BahaCore

final class ImportTests: XCTestCase {
    let uuid = "01234567-89ab-cdef-0123-456789abcdef"
    var basic: String { "vless://\(uuid)@example.com:443?security=tls&type=tcp#my%20server" }
    var reality: String { "vless://\(uuid)@example.com:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=example.org&pbk=\(Data(repeating: 1, count: 32).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""))&sid=aabb#reality" }

    func testVLESSFieldsAndDecodedName() throws {
        let profile = try ImportParser.profile(basic)
        XCTAssertEqual(profile.host, "example.com")
        XCTAssertEqual(profile.port, 443)
        XCTAssertEqual(profile.name, "my server")
        XCTAssertEqual(profile.detail, "vless · tls")
    }
    func testIPv6Endpoint() throws {
        let profile = try ImportParser.profile("vless://\(uuid)@[2001:db8::1]:443?security=tls")
        XCTAssertEqual(profile.host, "2001:db8::1")
    }
    func testPlainAndBase64Subscriptions() throws {
        let plain = "# comment\n\(basic)\r\n\(reality)\n"
        XCTAssertEqual(try ImportParser.parse(plain).count, 2)
        XCTAssertEqual(try ImportParser.parse(Data(plain.utf8).base64EncodedString()).count, 2)
    }
    func testUnsupportedLineFailsWholeImport() {
        XCTAssertThrowsError(try ImportParser.parse(basic + "\ntrojan://password@example.com:443"))
    }
    func testBadUUIDAndPortAreRejected() {
        XCTAssertThrowsError(try ImportParser.profile("vless://not-a-uuid@example.com:443"))
        XCTAssertThrowsError(try ImportParser.profile("vless://\(uuid)@example.com:99999"))
        XCTAssertThrowsError(try ImportParser.profile("vless://\(uuid)@example.com:0"))
    }
    func testUnsupportedTransportAndInsecureTLSAreRejected() {
        XCTAssertThrowsError(try ImportParser.profile("vless://\(uuid)@example.com:443?security=tls&type=grpc"))
        XCTAssertThrowsError(try ImportParser.profile("vless://\(uuid)@example.com:443?security=tls&allowInsecure=1"))
    }
    func testRealityKeyAndShortIDAreChecked() {
        XCTAssertThrowsError(try ImportParser.profile("vless://\(uuid)@example.com:443?security=reality&pbk=bad"))
        XCTAssertThrowsError(try ImportParser.profile(reality.replacingOccurrences(of: "sid=aabb", with: "sid=xyz")))
    }
    func testVisionNeedsTCP() {
        XCTAssertThrowsError(try ImportParser.profile(reality.replacingOccurrences(of: "type=tcp", with: "type=ws")))
    }
    func testDuplicateParametersRejected() {
        XCTAssertThrowsError(try ImportParser.profile("vless://\(uuid)@example.com:443?security=tls&security=none"))
    }
    func testVMessBase64JSON() throws {
        let object: [String: Any] = ["v": "2", "ps": "vmess server", "add": "example.com", "port": "443", "id": uuid, "aid": "0", "net": "ws", "path": "/ws", "tls": "tls"]
        let link = "vmess://" + (try JSONSerialization.data(withJSONObject: object)).base64EncodedString()
        let profile = try ImportParser.profile(link)
        XCTAssertEqual(profile.protocolName, "vmess")
        let config = try JSONSerialization.jsonObject(with: Data(XrayConfiguration.make(profile: profile, dns: "1.1.1.1").utf8)) as! [String: Any]
        let outbound = (config["outbounds"] as! [[String: Any]])[0]
        XCTAssertEqual(outbound["protocol"] as? String, "vmess")
        XCTAssertEqual((outbound["streamSettings"] as? [String: Any])?["network"] as? String, "ws")
    }
    func testSubscriptionURLRequiresHTTPS() throws {
        XCTAssertEqual(try ImportParser.subscriptionURL("https://example.com/sub/token").host, "example.com")
        XCTAssertThrowsError(try ImportParser.subscriptionURL("http://example.com/sub"))
        XCTAssertThrowsError(try ImportParser.subscriptionURL("https://user:password@example.com/sub"))
    }
    func testSizeLimitAndEmptyBody() {
        XCTAssertThrowsError(try ImportParser.parse(String(repeating: "x", count: ImportParser.maximumBytes + 1)))
        XCTAssertThrowsError(try ImportParser.parse("\n# only a comment"))
        XCTAssertThrowsError(try ImportParser.parse("<html>server error</html>"))
    }
    func testRealityConfigurationPreservesParameters() throws {
        let profile = try ImportParser.profile(reality)
        let config = try JSONSerialization.jsonObject(with: Data(XrayConfiguration.make(profile: profile, dns: "9.9.9.9").utf8)) as! [String: Any]
        let outbound = (config["outbounds"] as! [[String: Any]])[0]
        let stream = outbound["streamSettings"] as! [String: Any]
        let settings = stream["realitySettings"] as! [String: Any]
        XCTAssertEqual(settings["serverName"] as? String, "example.org")
        XCTAssertEqual(settings["shortId"] as? String, "aabb")
        let users = ((outbound["settings"] as! [String: Any])["vnext"] as! [[String: Any]])[0]["users"] as! [[String: Any]]
        XCTAssertEqual(users[0]["flow"] as? String, "xtls-rprx-vision")
        XCTAssertNil(config["inbounds"]) // The packet tunnel bridge adds its actual socketpair TUN.
    }
    func testXHTTPPathHostAndMode() throws {
        let link = "vless://\(uuid)@example.com:443?security=tls&type=xhttp&path=%2Ftunnel&host=cdn.example.com&mode=packet-up"
        let json = try XrayConfiguration.make(profile: ImportParser.profile(link), dns: "1.1.1.1")
        let config = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let settings = ((config["outbounds"] as! [[String: Any]])[0]["streamSettings"] as! [String: Any])["xhttpSettings"] as! [String: Any]
        XCTAssertEqual(settings["path"] as? String, "/tunnel")
        XCTAssertEqual(settings["host"] as? String, "cdn.example.com")
        XCTAssertEqual(settings["mode"] as? String, "packet-up")
    }
}
