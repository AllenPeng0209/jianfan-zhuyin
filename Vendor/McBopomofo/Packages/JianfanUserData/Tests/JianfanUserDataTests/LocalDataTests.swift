import Foundation
import Testing
@testable import JianfanUserData

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("JianfanTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let overrideFixture = Data("""
[{"key":"(ㄐㄧˋ,計)","value":"紀","count":3,"timestamp":1000,"forceHighScore":true}]
""".utf8)

@Suite("Offline persistent learning")
struct LearningStoreTests {
    @Test("Choices survive a new store instance with their original counts")
    func roundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = LearningStore(directoryURL: directory)
        #expect(first.replaceOverrides(json: overrideFixture))
        first.flush()
        let reopened = LearningStore(directoryURL: directory)
        #expect(reopened.recordCount == 1)
        let rows = try #require(JSONSerialization.jsonObject(with: reopened.overrideJSON()) as? [[String: Any]])
        #expect(rows.first?["value"] as? String == "紀")
        #expect(rows.first?["count"] as? Int == 3)
        #expect(rows.first?["forceHighScore"] as? Bool == true)
    }

    @Test("A selected association moves ahead after restart without adding unrelated words")
    func associationRankingPersists() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = LearningStore(directoryURL: directory)
        for time in [1000.0, 1001.0, 1002.0] {
            first.recordAssociation(prefixReading: "ㄓㄨㄥ-ㄏㄨㄚˊ", prefixValue: "中華", reading: "b", value: "中華電信", timestamp: time)
        }
        first.flush()
        let reopened = LearningStore(directoryURL: directory)
        let order = reopened.rankAssociationIndices(prefixReading: "ㄓㄨㄥ-ㄏㄨㄚˊ", prefixValue: "中華", readings: ["a", "b", "c"], values: ["中華民國", "中華電信", "中華文化"], timestamp: 2000)
        #expect(order.map(\.intValue) == [1, 0, 2])
        let unrelated = reopened.rankAssociationIndices(prefixReading: "other", prefixValue: "別的詞", readings: ["a", "b", "c"], values: ["中華民國", "中華電信", "中華文化"], timestamp: 2000)
        #expect(unrelated.map(\.intValue) == [0, 1, 2])
    }

    @Test("Recent associations can outrank stale frequent choices")
    func recency() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directoryURL: directory)
        for _ in 0..<10 { store.recordAssociation(prefixReading: "p", prefixValue: "前", reading: "a", value: "舊", timestamp: 1000) }
        let now = 1000.0 + 120 * 86400
        for _ in 0..<2 { store.recordAssociation(prefixReading: "p", prefixValue: "前", reading: "b", value: "新", timestamp: now) }
        let order = store.rankAssociationIndices(prefixReading: "p", prefixValue: "前", readings: ["a", "b"], values: ["舊", "新"], timestamp: now)
        #expect(order.map(\.intValue) == [1, 0])
        store.flush()
    }

    @Test("A corrupt primary file recovers the last valid backup")
    func recovery() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directoryURL: directory)
        #expect(store.replaceOverrides(json: overrideFixture))
        store.flush()
        #expect(store.replaceOverrides(json: Data("[]".utf8)))
        store.flush()
        try Data("broken".utf8).write(to: directory.appendingPathComponent("learning-v1.json"))
        let recovered = LearningStore(directoryURL: directory)
        #expect(recovered.recordCount == 1)
    }

    @Test("Unknown newer schemas are preserved instead of overwritten")
    func newerSchema() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("learning-v1.json")
        let original = Data("{\"schemaVersion\":999,\"futureData\":true}".utf8)
        try original.write(to: file)
        let store = LearningStore(directoryURL: directory)
        #expect(!store.replaceOverrides(json: overrideFixture))
        store.flush()
        #expect(try Data(contentsOf: file) == original)
        #expect(store.lastError != nil)
    }

    @Test("Invalid snapshots cannot replace valid learning data")
    func invalidSnapshot() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directoryURL: directory)
        #expect(store.replaceOverrides(json: overrideFixture))
        #expect(!store.replaceOverrides(json: Data("[{\"count\":-1}]".utf8)))
        store.flush()
        #expect(LearningStore(directoryURL: directory).recordCount == 1)
    }

    @Test("Clearing removes saved choices and association rankings across restart")
    func clear() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearningStore(directoryURL: directory)
        #expect(store.replaceOverrides(json: overrideFixture))
        store.recordAssociation(prefixReading: "p", prefixValue: "前", reading: "b", value: "乙", timestamp: 1000)
        #expect(store.recordCount > 0)
        store.clear()
        store.flush()
        let reopened = LearningStore(directoryURL: directory)
        #expect(reopened.recordCount == 0)
        #expect(reopened.rankAssociationIndices(prefixReading: "p", prefixValue: "前", readings: ["a", "b"], values: ["甲", "乙"], timestamp: 1001).map(\.intValue) == [0, 1])
    }
}

@Suite("Personal phrase files")
struct LexiconStoreTests {
    @Test("The engine reading policy is enforced for both edits and imports")
    func readingPolicy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.txt")
        let store = UserLexiconStore(fileURL: file, readingValidator: { $0 == "ㄒㄧㄥ-ㄏㄜˊ" })
        try store.upsert(UserPhrase(phrase: "星河", reading: "ㄒㄧㄥ-ㄏㄜˊ"))
        let original = try Data(contentsOf: file)
        #expect(throws: (any Error).self) { try store.upsert(UserPhrase(phrase: "別字", reading: "ㄅㄧㄚˇ")) }
        let data = Data("{\"schemaVersion\":1,\"entries\":[{\"phrase\":\"別字\",\"reading\":\"ㄅㄧㄚˇ\"}]}".utf8)
        #expect(throws: (any Error).self) { try store.importJSON(data) }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test("Readings longer than the input engine can match are rejected before saving")
    func unsupportedReadingLength() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UserLexiconStore(fileURL: directory.appendingPathComponent("data.txt"))
        let word = UserPhrase(phrase: "一二三四五六七八九", reading: "ㄧ-ㄦˋ-ㄙㄢ-ㄙˋ-ㄨˇ-ㄌㄧㄡˋ-ㄑㄧ-ㄅㄚ-ㄐㄧㄡˇ")
        #expect(throws: (any Error).self) { try store.upsert(word) }
        #expect(try store.entries().isEmpty)
    }

    @Test("UTF-8 BOM and Windows line endings retain the first phrase")
    func windowsTextEncoding() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.txt")
        try "\u{feff}星河 ㄒㄧㄥ-ㄏㄜˊ\r\n".write(to: file, atomically: true, encoding: .utf8)
        let store = UserLexiconStore(fileURL: file)
        #expect(try store.entries() == [UserPhrase(phrase: "星河", reading: "ㄒㄧㄥ-ㄏㄜˊ")])
    }

    @Test("The phrase file and its recovery backup are private to the user")
    func backupPermissions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.txt")
        let store = UserLexiconStore(fileURL: file)
        try store.upsert(UserPhrase(phrase: "星河", reading: "ㄒㄧㄥ-ㄏㄜˊ"))
        try store.upsert(UserPhrase(phrase: "研討", reading: "ㄧㄢˊ-ㄊㄠˇ"))
        for url in [file, file.appendingPathExtension("bak")] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }

    @Test("Add and edit normalize readings while preserving comments, scores and other words")
    func editPreservesOriginalFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.txt")
        try "# Personal words\n研究 ㄧㄢˊ-ㄐㄧㄡˋ -1.5\n星河 ㄒㄧㄥ-ㄏㄜˊ\n".write(to: file, atomically: true, encoding: .utf8)
        let store = UserLexiconStore(fileURL: file)
        #expect(try store.entries().count == 2)
        try store.upsert(UserPhrase(phrase: "研討", reading: "ㄧㄢˊ ㄊㄠˇ"), replacing: UserPhrase(phrase: "研究", reading: "ㄧㄢˊ-ㄐㄧㄡˋ"))
        let content = try String(contentsOf: file)
        #expect(content.contains("# Personal words\n"))
        #expect(content.contains("研討 ㄧㄢˊ-ㄊㄠˇ -1.5"))
        #expect(content.contains("星河 ㄒㄧㄥ-ㄏㄜˊ"))
        #expect(!content.contains("研究 "))
    }

    @Test("Duplicate additions are idempotent and unusual Unicode names are supported")
    func duplicateAndUnicode() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UserLexiconStore(fileURL: directory.appendingPathComponent("data.txt"))
        let word = UserPhrase(phrase: "𠮷野", reading: "ㄐㄧˊ ㄧㄝˇ")
        try store.upsert(word)
        try store.upsert(word)
        #expect(try store.entries() == [UserPhrase(phrase: "𠮷野", reading: "ㄐㄧˊ-ㄧㄝˇ")])
    }

    @Test("Invalid readings cannot alter existing phrases")
    func invalidReading() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.txt")
        let original = "# Keep this file\n星河 ㄒㄧㄥ-ㄏㄜˊ\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        let store = UserLexiconStore(fileURL: file)
        #expect(throws: (any Error).self) { try store.upsert(UserPhrase(phrase: "錯誤", reading: "hello world")) }
        #expect(try String(contentsOf: file) == original)
    }

    @Test("Invalid import batches do not partially overwrite the phrase file")
    func atomicImport() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.txt")
        let original = "星河 ㄒㄧㄥ-ㄏㄜˊ\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        let store = UserLexiconStore(fileURL: file)
        let data = Data("{\"schemaVersion\":1,\"entries\":[{\"phrase\":\"研究\",\"reading\":\"ㄧㄢˊ-ㄐㄧㄡˋ\"},{\"phrase\":\"錯\",\"reading\":\"bad\"}]}".utf8)
        #expect(throws: (any Error).self) { try store.importJSON(data) }
        #expect(try String(contentsOf: file) == original)
    }

    @Test("Exported phrases import into a new directory without duplication")
    func backupRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = UserLexiconStore(fileURL: directory.appendingPathComponent("one/data.txt"))
        try first.upsert(UserPhrase(phrase: "星河", reading: "ㄒㄧㄥ-ㄏㄜˊ"))
        try first.upsert(UserPhrase(phrase: "研討", reading: "ㄧㄢˊ-ㄊㄠˇ"))
        let data = try first.exportJSON()
        let second = UserLexiconStore(fileURL: directory.appendingPathComponent("two/data.txt"))
        #expect(try second.importJSON(data) == 2)
        #expect(try second.importJSON(data) == 0)
        #expect(try second.entries().count == 2)
    }

    @Test("Deletion and later edits preserve phrases added externally")
    func externalChanges() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.txt")
        let store = UserLexiconStore(fileURL: file)
        let first = UserPhrase(phrase: "星河", reading: "ㄒㄧㄥ-ㄏㄜˊ")
        try store.upsert(first)
        var current = try String(contentsOf: file)
        current += "研究 ㄧㄢˊ-ㄐㄧㄡˋ\n"
        try current.write(to: file, atomically: true, encoding: .utf8)
        try store.remove(first)
        #expect(try store.entries() == [UserPhrase(phrase: "研究", reading: "ㄧㄢˊ-ㄐㄧㄡˋ")])
    }
}
