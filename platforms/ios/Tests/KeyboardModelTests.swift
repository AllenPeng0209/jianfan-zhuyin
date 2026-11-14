import XCTest
@testable import Jianfan

@MainActor
final class KeyboardModelTests: XCTestCase {
    var directory: URL!
    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("jianfan-tests-" + UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }
    func makeModel() throws -> KeyboardModel {
        let engine = try JFCoreEngine(resourceDirectory: Bundle.main.resourceURL!.appendingPathComponent("Dictionaries").path)
        return KeyboardModel(engine: engine, learningDirectory: directory, phrasesURL: nil)
    }
    func testTypingIsPreeditUntilCommittedAndBackspaceRespectsHostText() throws {
        let model = try makeModel()
        var output = ""
        var deletions = 0
        model.insertText = { output += $0 }
        model.deleteText = { deletions += 1 }
        for key in "su3cl3" { model.press(String(key)) }
        XCTAssertEqual(model.engine.composition, "你好")
        XCTAssertEqual(output, "")
        model.space()
        XCTAssertEqual(output, "你好")
        XCTAssertEqual(model.engine.composition, "")
        model.backspace()
        XCTAssertEqual(deletions, 1)
        model.press("s")
        model.backspace()
        XCTAssertEqual(deletions, 1)
        XCTAssertEqual(model.engine.composition, "")
    }
    func testChoiceAndScriptToggleSurviveNewKeyboardInstance() throws {
        let first = try makeModel()
        first.toggleScript()
        for key in "ru4" { first.press(String(key)) }
        let index = try XCTUnwrap(first.candidates.firstIndex { $0.value == "紀" })
        first.choose(index)
        first.flush()
        let second = try makeModel()
        XCTAssertFalse(second.engine.simplified)
        for key in "ru4" { second.press(String(key)) }
        XCTAssertEqual(second.engine.composition, "紀")
        second.press("s")
        second.toggleScript()
        XCTAssertEqual(second.engine.composition, "纪ㄋ")
    }
    func testChoosingAssociationInsertsFullPhraseOnce() throws {
        let model = try makeModel()
        for key in "5j/ cj86" { model.press(String(key)) }
        model.showAssociations()
        let first = try XCTUnwrap(model.candidates.first)
        model.choose(0)
        var output = ""
        model.insertText = { output += $0 }
        model.enter()
        XCTAssertEqual(output, first.value)
    }

    func testSharedSettingsDisableLearningAndClearCommandRunsOnce() throws {
        let model = try makeModel()
        var settings = KeyboardSettings()
        settings.learningEnabled = false
        model.apply(settings)
        for key in "ru4" { model.press(String(key)) }
        let index = try XCTUnwrap(model.candidates.firstIndex { $0.canonicalValue == "紀" })
        model.choose(index)
        XCTAssertEqual(model.learning.recordCount, 0)
        model.enter()
        settings.learningEnabled = true
        model.apply(settings)
        for key in "ru4" { model.press(String(key)) }
        model.choose(try XCTUnwrap(model.candidates.firstIndex { $0.canonicalValue == "紀" }))
        XCTAssertGreaterThan(model.learning.recordCount, 0)
        settings.resetToken = UUID().uuidString
        model.apply(settings)
        XCTAssertEqual(model.learning.recordCount, 0)
        model.enter()
        for key in "ru4" { model.press(String(key)) }
        model.choose(try XCTUnwrap(model.candidates.firstIndex { $0.canonicalValue == "紀" }))
        model.apply(settings)
        XCTAssertGreaterThan(model.learning.recordCount, 0)
    }
}
