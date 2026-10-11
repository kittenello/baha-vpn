import XCTest

final class ImportPersistenceTests: XCTestCase {
    func testJSONImportThroughUI() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-state"]
        app.launch()
        let add = app.buttons["добавить сервер"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let input = app.textViews["profile-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap()
        input.typeText(#"[{"remarks":"json-import-test","outbounds":[{"protocol":"trojan","settings":{"servers":[{"address":"example.com","port":443,"password":"test"}]}}]}]"#)
        app.buttons["готово"].tap(); app.buttons["импортировать"].tap()
        XCTAssertTrue(app.staticTexts["json-import-test"].firstMatch.waitForExistence(timeout: 10))
    }
    func testImportAndFavoriteSurviveAppRestart() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-state"]
        app.launch()
        let add = app.buttons["добавить сервер"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let input = app.textViews["profile-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("vless://01234567-89ab-cdef-0123-456789abcdef@example.com:443?security=tls&type=tcp#persistent-server")
        app.buttons["готово"].tap()
        app.buttons["импортировать"].tap()
        XCTAssertTrue(app.staticTexts["persistent-server"].firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["серверы"].tap()
        let favorite = app.buttons["в избранное"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        favorite.tap()
        app.terminate()

        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["persistent-server"].firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["серверы"].tap()
        XCTAssertTrue(app.buttons["убрать из избранного"].firstMatch.waitForExistence(timeout: 5))
    }
}
