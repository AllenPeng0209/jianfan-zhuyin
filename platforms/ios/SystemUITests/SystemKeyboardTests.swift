import XCTest

final class SystemKeyboardTests: XCTestCase {
    func testInstalledExtensionTypesIntoTheContainingAppWithoutFullAccess() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)"]
        settings.launch()
        settings.staticTexts["General"].firstMatch.tap()
        settings.staticTexts["Keyboard"].firstMatch.tap()
        settings.cells["KEYBOARDS"].tap()
        let name = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "簡繁注音", "Jianfan")
        if !settings.staticTexts.matching(name).firstMatch.exists {
            settings.cells["AddNewKeyboard"].tap()
            XCTAssertTrue(settings.staticTexts.matching(name).firstMatch.waitForExistence(timeout: 5))
            settings.staticTexts.matching(name).firstMatch.tap()
        }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)"]
        app.launch()
        app.cells["home-1-0"].tap()
        app.buttons["add-phrase"].tap()
        app.textFields["phrase-word"].tap()
        if !app.buttons["key-s"].exists {
            let globe = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR identifier == %@ OR label == %@ OR label == %@", "Next keyboard", "emoji", "Next keyboard", "下一個鍵盤")).firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5))
            XCTAssertTrue(globe.isHittable,"Disconnect the Simulator hardware keyboard before running this system-keyboard integration test.")
            globe.press(forDuration: 1.2)
            let button = app.buttons.matching(name).firstMatch
            if button.exists { button.tap() }
            else { app.staticTexts.matching(name).firstMatch.tap() }
        }
        XCTAssertTrue(app.buttons["key-s"].waitForExistence(timeout: 8))
        for key in ["s","u","3","c","l","3"] { app.buttons["key-" + key].tap() }
        XCTAssertEqual(app.staticTexts["preedit"].label,"你好")
        app.buttons["commit"].tap()
        XCTAssertEqual(app.textFields["phrase-word"].value as? String,"你好")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Jianfan-installed-iOS-extension"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
