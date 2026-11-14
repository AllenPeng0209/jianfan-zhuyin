import Foundation
import XCTest
import JianfanUserData
@testable import McBopomofo

final class OfflinePersonalizationTests: XCTestCase {
    private var savedLearning = true
    private var savedConversion = true
    private var savedAssociation = false
    private var savedLayout: KeyboardLayout = .standard

    override func setUpWithError() throws {
        guard Bundle.main.bundleIdentifier?.contains(".Development") == true,
              LanguageModelManager.dataFolderPath.contains("JianfanZhuyin-Tests-") else {
            throw XCTSkip("Use scripts/test-macos.sh to isolate the daily input method")
        }
        savedLearning = Preferences.localLearningEnabled
        savedConversion = Preferences.chineseConversionEnabled
        savedAssociation = Preferences.associatedPhrasesEnabled
        savedLayout = Preferences.keyboardLayout
        Preferences.localLearningEnabled = true
        Preferences.chineseConversionEnabled = false
        Preferences.associatedPhrasesEnabled = false
        Preferences.keyboardLayout = .standard
        LanguageModelManager.loadDataModels()
        LanguageModelManager.setupDataModelValueConverter()
        _ = LanguageModelManager.checkIfUserLanguageModelFilesExist()
    }

    override func tearDownWithError() throws {
        LanguageModelManager.flushLearning()
        Preferences.localLearningEnabled = savedLearning
        Preferences.chineseConversionEnabled = savedConversion
        Preferences.associatedPhrasesEnabled = savedAssociation
        Preferences.keyboardLayout = savedLayout
    }

    private func type(_ keys: String, using handler: KeyHandler) -> InputState {
        handler.syncWithPreferences()
        var state: InputState = InputState.Empty()
        for key in keys {
            let text = String(key)
            let input = KeyHandlerInput(inputText: text, keyCode: 0, charCode: charCode(text), flags: [], isVerticalMode: false)
            _ = handler.handle(input: input, state: state) { state = $0 } errorCallback: { XCTFail("Valid Bopomofo input failed") }
        }
        return state
    }

    func test01WritesChoiceForProcessRestart() {
        LanguageModelManager.clearLearning()
        let handler = KeyHandler()
        _ = type("ru4", using: handler)
        handler.fixNode(reading: "ㄐㄧˋ", value: "紀", originalCursorIndex: 1, useMoveCursorAfterSelectionSetting: false)
        XCTAssertEqual((handler.buildInputtingState() as? InputState.Inputting)?.composingBuffer, "紀")
        LanguageModelManager.flushLearning()
        XCTAssertGreaterThan(LanguageModelManager.learningRecordCount(), 0)
    }

    func test02RestoresChoiceWithoutSelectingAgain() {
        XCTAssertGreaterThan(LanguageModelManager.learningRecordCount(), 0)
        let state = type("ru4", using: KeyHandler())
        XCTAssertEqual((state as? InputState.Inputting)?.composingBuffer, "紀")
    }

    func test03DisabledLearningDoesNotRecordChoices() {
        LanguageModelManager.clearLearning()
        Preferences.localLearningEnabled = false
        let handler = KeyHandler()
        _ = type("ru4", using: handler)
        handler.fixNode(reading: "ㄐㄧˋ", value: "紀", originalCursorIndex: 1, useMoveCursorAfterSelectionSetting: false)
        LanguageModelManager.flushLearning()
        XCTAssertEqual(LanguageModelManager.learningRecordCount(), 0)
    }

    func test04AssociationRankingPreservesCandidatesAndPauseRestoresBaseline() throws {
        LanguageModelManager.clearLearning()
        let handler = KeyHandler()
        let inputting = type("5j/ cj86", using: handler)
        let params = BuildAssociatedPhraseParams()
        params.previousState = inputting
        params.prefixCursorIndex = 2
        params.reading = "ㄓㄨㄥ-ㄏㄨㄚˊ"
        params.value = "中華"
        let baseline = try XCTUnwrap(handler.buildAssociatedPhraseState(with: params) as? InputState.AssociatedPhrases)
        XCTAssertGreaterThan(baseline.candidates.count, 3)
        let selected = baseline.candidates[baseline.candidates.count / 2]
        LanguageModelManager.recordAssociation(prefixReading: params.reading, prefixValue: params.value,
                                              reading: selected.reading, value: selected.value)
        let ranked = try XCTUnwrap(handler.buildAssociatedPhraseState(with: params) as? InputState.AssociatedPhrases)
        XCTAssertEqual(ranked.candidates.first?.value, selected.value)
        XCTAssertEqual(Set(ranked.candidates.map(\.value)), Set(baseline.candidates.map(\.value)))
        Preferences.localLearningEnabled = false
        let paused = try XCTUnwrap(handler.buildAssociatedPhraseState(with: params) as? InputState.AssociatedPhrases)
        XCTAssertEqual(paused.candidates.map(\.value), baseline.candidates.map(\.value))
    }

    func test05ManagedWordsAreLoadedByTheInputEngine() throws {
        let store = UserLexiconStore(fileURL: URL(fileURLWithPath: LanguageModelManager.userPhrasesDataPathMcBopomofo))
        let word = UserPhrase(phrase: "星禾計畫", reading: "ㄒㄧㄥ-ㄏㄜˊ-ㄐㄧˋ-ㄏㄨㄚˋ")
        try store.upsert(word)
        defer {
            try? store.remove(word)
            LanguageModelManager.loadUserPhrases(enableForPlainBopomofo: false)
        }
        LanguageModelManager.loadUserPhrases(enableForPlainBopomofo: false)
        let state = type("vu/ ck6ru4cj84", using: KeyHandler())
        XCTAssertEqual((state as? InputState.Inputting)?.composingBuffer, "星禾計畫")
    }

    func test06ReadingValidationUsesActualPhoneticMappings() {
        XCTAssertTrue(LanguageModelManager.isUserPhraseReadingSupported("ㄒㄧㄥ-ㄏㄜˊ"))
        XCTAssertTrue(LanguageModelManager.isUserPhraseReadingSupported("ㄐㄧˋ"))
        XCTAssertFalse(LanguageModelManager.isUserPhraseReadingSupported("ㄅㄧㄚˇ"))
        XCTAssertFalse(LanguageModelManager.isUserPhraseReadingSupported("ㄅㄅㄧ"))
        XCTAssertFalse(LanguageModelManager.isUserPhraseReadingSupported("ㄧ-ㄧ-ㄧ-ㄧ-ㄧ-ㄧ-ㄧ-ㄧ-ㄧ"))
        XCTAssertEqual(LanguageModelManager.suggestedUserPhraseReading("电脑"), "ㄉㄧㄢˋ-ㄋㄠˇ")
    }
}
