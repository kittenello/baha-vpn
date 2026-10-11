import XCTest
@testable import BahaCore

final class ExtendedImportTests: XCTestCase {
    let uuid = "01234567-89ab-cdef-0123-456789abcdef"
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    func config(_ link: String, fixture: String? = nil) throws -> [String: Any] {
        let profile = try ImportParser.profile(link)
        let json = try XrayConfiguration.make(profile: profile, dns: "1.1.1.1")
        if let path = ProcessInfo.processInfo.environment["BAHA_FIXTURES"], let fixture {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: url.appendingPathComponent(fixture + ".json"))
        }
        return try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }
    func testTrojanGRPC() throws {
        let object = try config("trojan://password@example.com:443?type=grpc&serviceName=mygrpc&security=tls#trojan", fixture: "trojan-grpc")
        let outbound = (object["outbounds"] as! [[String: Any]])[0]
        XCTAssertEqual(outbound["protocol"] as? String, "trojan")
        XCTAssertEqual(((outbound["streamSettings"] as! [String: Any])["grpcSettings"] as! [String: Any])["serviceName"] as? String, "mygrpc")
    }
    func testShadowsocksSIP002AndLegacy() throws {
        let auth = Data("aes-128-gcm:password".utf8).base64EncodedString()
        let object = try config("ss://\(auth)@example.com:8388#ss", fixture: "shadowsocks")
        let outbound = (object["outbounds"] as! [[String: Any]])[0]
        XCTAssertEqual(outbound["protocol"] as? String, "shadowsocks")
        let legacy = "ss://" + Data("aes-128-gcm:password@example.com:8388".utf8).base64EncodedString()
        XCTAssertEqual(try ImportParser.profile(legacy).port, 8388)
    }
    func testHysteria2Obfuscation() throws {
        let object = try config("hy2://user:password@example.com:443?sni=example.org&obfs=salamander&obfs-password=salty&up=100&down=100", fixture: "hysteria2")
        let outbound = (object["outbounds"] as! [[String: Any]])[0]
        XCTAssertEqual(outbound["protocol"] as? String, "hysteria")
        let stream = outbound["streamSettings"] as! [String: Any]
        XCTAssertEqual((stream["hysteriaSettings"] as! [String: Any])["auth"] as? String, "user:password")
        XCTAssertNotNil(stream["finalmask"])
    }
    func testWireGuardLink() throws {
        let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+/=")))!
        let object = try config("wireguard://\(escaped)@example.com:51820?publickey=\(escaped)&address=10.0.0.2/32&reserved=1,2,3", fixture: "wireguard")
        let settings = (object["outbounds"] as! [[String: Any]])[0]["settings"] as! [String: Any]
        XCTAssertEqual(settings["noKernelTun"] as? Bool, true)
        XCTAssertEqual(settings["reserved"] as? String, "AQID")
    }
    func testVLESSAndVMessGRPC() throws {
        let object = try config("vless://\(uuid)@example.com:443?type=grpc&serviceName=svc&security=tls", fixture: "vless-grpc")
        XCTAssertEqual(((object["outbounds"] as! [[String: Any]])[0]["streamSettings"] as! [String: Any])["network"] as? String, "grpc")
        let vmess: [String: Any] = ["add": "example.com", "id": uuid, "port": 443, "net": "grpc", "path": "service", "tls": "tls"]
        _ = try config("vmess://" + JSONSerialization.data(withJSONObject: vmess).base64EncodedString(), fixture: "vmess-grpc")
    }
    func testJSONSubscriptionArrayAndPreservedRules() throws {
        let raw = """
        [{"remarks":"json server","outbounds":[{"tag":"proxy","protocol":"trojan","settings":{"servers":[{"address":"example.com","port":443,"password":"test"}]},"streamSettings":{"security":"tls","tlsSettings":{"serverName":"example.com"}}}],"dns":{"servers":["9.9.9.9"]},"routing":{"domainStrategy":"IPIfNonMatch","rules":[{"type":"field","domain":["domain:example.org"],"outboundTag":"proxy"}]}}]
        """
        let profiles = try ImportParser.parse(raw)
        XCTAssertEqual(profiles.count, 1); XCTAssertEqual(profiles[0].name, "json server")
        let object = try config(profiles[0].link, fixture: "raw-json-routing")
        XCTAssertEqual((object["dns"] as! [String: Any])["servers"] as? [String], ["9.9.9.9"])
        XCTAssertEqual((object["routing"] as! [String: Any])["domainStrategy"] as? String, "IPIfNonMatch")
        XCTAssertEqual(((object["routing"] as! [String: Any])["rules"] as! [[String: Any]]).count, 1)
        XCTAssertEqual(try ImportParser.parse(Data(raw.utf8).base64EncodedString()).count, 1)
        XCTAssertEqual(try ImportParser.parse(Data(("\u{feff}\n  " + raw).utf8).base64EncodedString()).count, 1)
    }
    func testWireGuardConf() throws {
        let raw = """
        [Interface]
        PrivateKey = \(key)
        Address = 10.0.0.2/32
        DNS = 9.9.9.9
        [Peer]
        PublicKey = \(key)
        Endpoint = example.com:51820
        AllowedIPs = 0.0.0.0/0, ::/0
        PersistentKeepalive = 25
        """
        let profiles = try ImportParser.parse(raw)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].port, 51820)
        _ = try config(profiles[0].link, fixture: "wireguard-conf")
    }
    func testRoutingRulesAndBackwardCompatibleSettings() throws {
        let old = Data(#"{"autoRefresh":true,"refreshHours":6,"connectOnDemand":false,"dns":"1.1.1.1"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ClientSettings.self, from: old).routingRules)
        let profile = try ImportParser.profile("trojan://password@example.com:443")
        let rules = [TrafficRule(kind: .domain, action: .block, patterns: ["geosite:category-ads-all"]),
                     TrafficRule(kind: .port, action: .direct, patterns: ["80", "8000-9000"])]
        let json = try XrayConfiguration.make(profile: profile, dns: "1.1.1.1", rules: rules, bypassLAN: true)
        if let path = ProcessInfo.processInfo.environment["BAHA_FIXTURES"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: directory.appendingPathComponent("routing-geosite.json"))
        }
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        XCTAssertEqual((object["outbounds"] as! [[String: Any]]).count, 3)
        XCTAssertEqual(((object["routing"] as! [String: Any])["rules"] as! [[String: Any]]).count, 3)
    }
    func testInvalidJSONDoesNotFallBackToShareLinkLines() {
        XCTAssertThrowsError(try ImportParser.parse("{\n\"outbounds\": broken\n}")) { error in XCTAssertTrue(error.localizedDescription.contains("json")) }
    }
}
