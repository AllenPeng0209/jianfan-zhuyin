import XCTest

final class TypingUITests: XCTestCase {
    private func capture(_ name: String, app: XCUIApplication) {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notice = system.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Apple Intelligence")).firstMatch
        if notice.exists && notice.isHittable { notice.swipeUp() }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testManageWordAndAutomaticallyFillItsReading() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)"]
        app.launch()
        app.cells["home-1-0"].tap()
        app.buttons["add-phrase"].tap()
        let word = app.textFields["phrase-word"]
        word.tap(); word.typeText("星禾計畫")
        app.buttons["auto-reading"].tap()
        XCTAssertEqual(app.textFields["phrase-reading"].value as? String,"ㄒㄧㄥ-ㄏㄜˊ-ㄐㄧˋ-ㄏㄨㄚˋ")
        app.buttons["save-phrase"].tap()
        XCTAssertTrue(app.staticTexts["星禾計畫"].waitForExistence(timeout: 5))
        capture("Jianfan-iOS-dictionary", app: app)
        let cell = app.cells.containing(.staticText,identifier: "星禾計畫").firstMatch
        cell.swipeLeft()
        app.buttons["刪除"].tap()
        XCTAssertFalse(app.staticTexts["星禾計畫"].exists)
    }
    func testVisibleKeyboardCommitsAndKeepsCompositionDuringScriptSwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)"]
        app.launch()
        capture("Jianfan-iOS-home", app: app)
        app.cells["home-0-1"].tap()
        if app.buttons["toggle-script"].label == "切換為簡體" { app.buttons["toggle-script"].tap() }
        for key in ["g","j","space","b","j","4","s"] {
            app.buttons[key == "space" ? "space" : "key-" + key].tap()
        }
        XCTAssertEqual(app.staticTexts["preedit"].label,"输入ㄋ")
        app.buttons["toggle-script"].tap()
        XCTAssertEqual(app.staticTexts["preedit"].label,"輸入ㄋ")
        capture("Jianfan-iOS-composition", app: app)
        app.buttons["backspace"].tap()
        app.buttons["commit"].tap()
        XCTAssertEqual(app.textViews["demo-output"].value as? String,"輸入")
        capture("Jianfan-iOS-keyboard", app: app)
    }
}
