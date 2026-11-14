import Foundation

public struct UserPhrase: Codable, Equatable, Identifiable {
    public var phrase: String
    public var reading: String
    public var id: String { phrase + "\u{1f}" + reading }
    public init(phrase: String, reading: String) { self.phrase = phrase; self.reading = reading }

    public func validated() throws -> UserPhrase {
        let word = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.count <= 80, !word.contains(where: { $0.isWhitespace }),
              !word.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw UserDataError.invalidPhrase }
        let syllables = reading.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map(String.init)
        guard !syllables.isEmpty else { throw UserDataError.invalidReading }
        guard syllables.count <= 8 else { throw UserDataError.readingTooLong }
        let normalized = try syllables.map { source -> String in
            var syllable = source.replacingOccurrences(of: "ˉ", with: "")
            if syllable.hasPrefix("˙") { syllable = String(syllable.dropFirst()) + "˙" }
            guard syllable.range(of: "^[ㄅ-ㄩ]+[ˊˇˋ˙]?$", options: .regularExpression) != nil else { throw UserDataError.invalidReading }
            return syllable
        }
        return UserPhrase(phrase: word, reading: normalized.joined(separator: "-"))
    }
}

public enum UserDataError: Error, LocalizedError {
    case invalidPhrase, invalidReading, readingTooLong, invalidArchive, unsupportedVersion, missingOriginal
    public var errorDescription: String? {
        let key: String
        switch self {
        case .invalidPhrase: key = "Enter a word without spaces or line breaks."
        case .invalidReading: key = "Enter Bopomofo syllables separated by spaces or hyphens."
        case .readingTooLong: key = "Use up to eight syllables. Short readings can expand into longer words."
        case .invalidArchive: key = "The phrase backup is invalid. No phrases were changed."
        case .unsupportedVersion: key = "This backup was created by a newer version."
        case .missingOriginal: key = "This word changed in another window. Reload the list and try again."
        }
        return NSLocalizedString(key, bundle: .module, comment: "")
    }
}

private struct PhraseArchive: Codable { var schemaVersion = 1; var entries: [UserPhrase] }
private struct PhraseLine { var text: String; var entry: UserPhrase?; var suffix: String }

public final class UserLexiconStore {
    public let fileURL: URL
    private let readingValidator: (String) -> Bool
    public init(fileURL: URL, readingValidator: @escaping (String) -> Bool = { _ in true }) {
        self.fileURL = fileURL
        self.readingValidator = readingValidator
    }

    private func read() throws -> String {
        guard fileURL.isFileURL else { throw UserDataError.invalidArchive }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return "" }
        guard let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber,
              size.intValue <= 16 * 1024 * 1024 else { throw UserDataError.invalidArchive }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func lines(_ content: String) -> [PhraseLine] {
        var source = content.components(separatedBy: "\n")
        if source.last == "" { source.removeLast() }
        let regex = try! NSRegularExpression(pattern: "^(\\S+)[\\t ]+(\\S+)(.*)$")
        return source.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("#"),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let wordRange = Range(match.range(at: 1), in: line),
                  let readingRange = Range(match.range(at: 2), in: line),
                  let suffixRange = Range(match.range(at: 3), in: line),
                  let entry = try? UserPhrase(phrase: String(line[wordRange]), reading: String(line[readingRange])).validated() else {
                return PhraseLine(text: line, entry: nil, suffix: "")
            }
            return PhraseLine(text: line, entry: entry, suffix: String(line[suffixRange]))
        }
    }

    public func entries() throws -> [UserPhrase] {
        var seen = Set<String>()
        return lines(try read()).compactMap(\.entry).filter { seen.insert($0.id).inserted }
    }

    private func write(_ output: [String], original: String) throws {
        let content = output.isEmpty ? "" : output.joined(separator: "\n") + "\n"
        guard content != original else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !original.isEmpty {
            let backup = fileURL.appendingPathExtension("bak")
            try Data(original.utf8).write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try Data(content.utf8).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func upsert(_ entry: UserPhrase, replacing original: UserPhrase? = nil) throws {
        let entry = try entry.validated()
        guard readingValidator(entry.reading) else { throw UserDataError.invalidReading }
        let originalID = try original?.validated().id
        let content = try read()
        let source = lines(content)
        if let originalID, !source.contains(where: { $0.entry?.id == originalID }) { throw UserDataError.missingOriginal }
        let alreadyExists = source.contains { $0.entry?.id == entry.id && $0.entry?.id != originalID }
        var inserted = false
        var output: [String] = []
        for line in source {
            if let originalID, line.entry?.id == originalID {
                if !alreadyExists && !inserted { output.append(entry.phrase + " " + entry.reading + line.suffix); inserted = true }
            } else if line.entry?.id == entry.id {
                if !inserted { output.append(line.text); inserted = true }
            } else {
                output.append(line.text)
            }
        }
        if !inserted { output.append(entry.phrase + " " + entry.reading) }
        try write(output, original: content)
    }

    public func remove(_ entry: UserPhrase) throws {
        let id = try entry.validated().id
        let content = try read()
        let source = lines(content)
        guard source.contains(where: { $0.entry?.id == id }) else { throw UserDataError.missingOriginal }
        try write(source.filter { $0.entry?.id != id }.map(\.text), original: content)
    }

    @discardableResult public func importJSON(_ data: Data) throws -> Int {
        guard data.count <= 8 * 1024 * 1024 else { throw UserDataError.invalidArchive }
        let archive: PhraseArchive
        do { archive = try JSONDecoder().decode(PhraseArchive.self, from: data) }
        catch { throw UserDataError.invalidArchive }
        guard archive.schemaVersion == 1 else { throw UserDataError.unsupportedVersion }
        guard archive.entries.count <= 100000 else { throw UserDataError.invalidArchive }
        let validated = try archive.entries.map { try $0.validated() }
        guard validated.allSatisfy({ readingValidator($0.reading) }) else { throw UserDataError.invalidReading }
        let content = try read()
        let source = lines(content)
        var seen = Set(source.compactMap { $0.entry?.id })
        var output = source.map(\.text)
        var added = 0
        for entry in validated where seen.insert(entry.id).inserted {
            output.append(entry.phrase + " " + entry.reading)
            added += 1
        }
        if added > 0 { try write(output, original: content) }
        return added
    }

    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(PhraseArchive(entries: entries()))
    }
}
