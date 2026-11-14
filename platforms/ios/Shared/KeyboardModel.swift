import Foundation
import JianfanUserData

@MainActor
final class KeyboardModel {
    let engine: JFCoreEngine
    let learning: LearningStore
    private(set) var candidates: [JFCoreCandidate] = []
    private(set) var showingAssociations = false
    var insertText: (String) -> Void = { _ in }
    var deleteText: () -> Void = {}
    private let resetURL: URL
    private let modeURL: URL
    private var settingsRevision: String?
    private struct SavedMode: Codable { var simplified: Bool; var revision: String? }
    init(engine: JFCoreEngine, learningDirectory: URL, phrasesURL: URL?) {
        self.engine = engine
        self.learning = LearningStore(directoryURL: learningDirectory)
        self.resetURL = learningDirectory.appendingPathComponent("applied-reset.txt")
        self.modeURL = learningDirectory.appendingPathComponent("mode-v1.json")
        if let data = try? Data(contentsOf: modeURL), data.count < 65536,
           let saved = try? JSONDecoder().decode(SavedMode.self,from: data) {
            engine.simplified = saved.simplified; settingsRevision = saved.revision
        }
        engine.restoreChoices(learning.overrideJSON())
        if let phrasesURL {
            engine.reloadUserPhrases(phrasesURL.path, excluded: "")
        }
    }
    private func refresh() {
        showingAssociations = false
        candidates = engine.openCandidates()
    }
    func press(_ key: String) {
        if key == " " { space(); return }
        if engine.key(key, timestamp: Date().timeIntervalSince1970) { refresh() }
    }
    func backspace() {
        if engine.composition.isEmpty { deleteText() }
        else { engine.backspace(); refresh() }
    }
    func space() {
        if !engine.phonetic.isEmpty { _ = engine.key(" ", timestamp: Date().timeIntervalSince1970); refresh() }
        else if !engine.composition.isEmpty { insertText(engine.commit()); refresh() }
        else { insertText(" ") }
    }
    func enter() {
        insertText(engine.composition.isEmpty ? "\n" : engine.commit())
        refresh()
    }
    func choose(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        let now = Date().timeIntervalSince1970
        if showingAssociations {
            let candidate = candidates[index]
            let prefix = engine.associationPrefix()
            if engine.selectAssociation(UInt(index), timestamp: now), engine.learningEnabled {
                learning.recordAssociation(prefixReading: prefix[0], prefixValue: prefix[1], reading: candidate.reading,
                                           value: candidate.canonicalValue, timestamp: now)
            }
        } else { _ = engine.selectCandidate(UInt(index), timestamp: now) }
        if engine.learningEnabled { _ = learning.replaceOverrides(json: engine.choiceSnapshot()) }
        refresh()
    }
    func showAssociations() {
        let rows = engine.openAssociations()
        let prefix = engine.associationPrefix()
        if engine.learningEnabled {
            let order = learning.rankAssociationIndices(prefixReading: prefix[0], prefixValue: prefix[1],
                readings: rows.map(\.reading), values: rows.map(\.canonicalValue), timestamp: Date().timeIntervalSince1970)
            engine.rankAssociations(order)
            candidates = order.map { rows[$0.intValue] }
        } else { candidates = rows }
        showingAssociations = true
    }
    private func saveMode() {
        try? FileManager.default.createDirectory(at: modeURL.deletingLastPathComponent(),withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(SavedMode(simplified: engine.simplified,revision: settingsRevision)) {
            try? data.write(to: modeURL,options: .atomic)
        }
    }
    func toggleScript() { engine.simplified.toggle(); saveMode(); refresh() }
    func apply(_ settings: KeyboardSettings) {
        engine.learningEnabled = settings.learningEnabled
        if settingsRevision != settings.revision {
            engine.simplified = settings.simplified; settingsRevision = settings.revision; saveMode()
        }
        let applied = (try? String(contentsOf: resetURL, encoding: .utf8)) ?? ""
        if !settings.resetToken.isEmpty && settings.resetToken != applied {
            learning.clear()
            learning.flush()
            engine.clearLearning()
            try? FileManager.default.createDirectory(at: resetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(settings.resetToken.utf8).write(to: resetURL, options: .atomic)
        }
        refresh()
    }
    func flush() { learning.flush() }
}
