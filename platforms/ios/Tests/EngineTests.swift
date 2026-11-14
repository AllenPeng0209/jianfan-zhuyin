import XCTest
@testable import Jianfan

final class EngineTests: XCTestCase {
    func makeEngine() throws -> JFCoreEngine {
        try JFCoreEngine(resourceDirectory: Bundle.main.resourceURL!.appendingPathComponent("Dictionaries").path)
    }
    func testStandardZhuyinAndIncompleteScriptSwitch() throws {
        let engine = try makeEngine()
        for key in "gj bj4s" { XCTAssertTrue(engine.key(String(key), timestamp: 1000)) }
        XCTAssertEqual(engine.composition, "输入ㄋ")
        engine.simplified = false
        XCTAssertEqual(engine.composition, "輸入ㄋ")
        XCTAssertEqual(engine.commit(), "輸入ㄋ")
        XCTAssertEqual(engine.composition, "")
    }
    func testSeparateEngineRestoresRareChoice() throws {
        let first = try makeEngine()
        first.simplified = false
        for key in "ru4" { XCTAssertTrue(first.key(String(key), timestamp: 1000)) }
        let candidates = first.openCandidates()
        let index = try XCTUnwrap(candidates.firstIndex { $0.value == "紀" })
        XCTAssertTrue(first.selectCandidate(UInt(index), timestamp: 1000))
        let second = try makeEngine()
        second.simplified = false
        second.restoreChoices(first.choiceSnapshot())
        for key in "ru4" { XCTAssertTrue(second.key(String(key), timestamp: 1001)) }
        XCTAssertEqual(second.composition, "紀")
    }
}
