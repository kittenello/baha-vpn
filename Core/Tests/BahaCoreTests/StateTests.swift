import XCTest
@testable import BahaCore

final class StateTests: XCTestCase {
    let link = "vless://01234567-89ab-cdef-0123-456789abcdef@example.com:443?security=tls&type=tcp#first"
    func testDuplicatesIgnoreDisplayNameAndQueryOrder() throws {
        var state = ClientState()
        let first = try ImportParser.profile(link)
        let second = try ImportParser.profile(link.replacingOccurrences(of: "security=tls&type=tcp#first", with: "type=tcp&security=tls#second"))
        XCTAssertEqual(state.add([first, second]), 1)
        XCTAssertEqual(state.selectedID, first.id)
    }
    func testRefreshKeepsIDSelectionFavoriteAndUpdatesName() throws {
        var state = ClientState()
        let subscription = ServerSubscription(name: "test", url: URL(string: "https://example.com/sub")!)
        state.subscriptions.append(subscription)
        let first = try ImportParser.profile(link)
        state.replace(subscriptionID: subscription.id, profiles: [first], usage: nil)
        state.profiles[0].isFavorite = true
        let selected = state.selectedID
        let second = try ImportParser.profile(link.replacingOccurrences(of: "#first", with: "#second"))
        state.replace(subscriptionID: subscription.id, profiles: [second, second], usage: nil)
        XCTAssertEqual(state.profiles.count, 1)
        XCTAssertEqual(state.selectedID, selected)
        XCTAssertTrue(state.profiles[0].isFavorite)
        XCTAssertEqual(state.profiles[0].name, "second")
    }
    func testRemoveSubscriptionDoesNotDeletePersonalProfiles() throws {
        var state = ClientState()
        let subscription = ServerSubscription(name: "test", url: URL(string: "https://example.com/sub")!)
        state.subscriptions.append(subscription)
        state.replace(subscriptionID: subscription.id, profiles: [try ImportParser.profile(link)], usage: nil)
        _ = state.add([try ImportParser.profile(link)])
        state.removeSubscription(subscription.id)
        XCTAssertEqual(state.profiles.count, 1)
        XCTAssertNil(state.profiles[0].subscriptionID)
        XCTAssertEqual(state.selectedID, state.profiles[0].id)
    }
    func testRoundtripPersistsAllState() throws {
        var state = ClientState()
        _ = state.add([try ImportParser.profile(link)])
        state.profiles[0].isFavorite = true
        state.settings.dns = "9.9.9.9"
        state.settings.connectOnDemand = true
        let restored = try JSONDecoder().decode(ClientState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state, restored)
    }
    func testFailedImportDoesNotEraseSubscription() throws {
        var state = ClientState()
        let subscription = ServerSubscription(name: "test", url: URL(string: "https://example.com/sub")!)
        state.subscriptions.append(subscription)
        state.replace(subscriptionID: subscription.id, profiles: [try ImportParser.profile(link)], usage: nil)
        let before = state
        do {
            let incoming = try ImportParser.parse(link + "\ninvalid")
            state.replace(subscriptionID: subscription.id, profiles: incoming, usage: nil)
            XCTFail("invalid import should throw")
        } catch { XCTAssertEqual(state, before) }
    }
    func testQuotaHeaderAndOverflow() {
        let usage = SubscriptionUsage(header: "upload=10; download=20; total=100; expire=1700000000")
        XCTAssertEqual(usage.traffic, 30)
        XCTAssertEqual(usage.total, 100)
        XCTAssertNotNil(usage.expires)
        let large = SubscriptionUsage(header: "upload=9223372036854775807; download=1")
        XCTAssertEqual(large.traffic, Int64.max)
    }
}
