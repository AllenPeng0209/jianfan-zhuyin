import Foundation

private struct ChoiceRecord: Codable {
    var key: String
    var value: String
    var count: Int
    var timestamp: Double
    var forceHighScore: Bool
    var isValid: Bool {
        !key.isEmpty && key.utf8.count <= 4096 && !value.isEmpty && value.utf8.count <= 1024
            && (1...1_000_000).contains(count) && timestamp.isFinite && timestamp >= 0
    }
}

private struct AssociationRecord: Codable {
    var prefixReading: String
    var prefixValue: String
    var reading: String
    var value: String
    var count: Int
    var timestamp: Double
    var key: String { [prefixReading, prefixValue, reading, value].joined(separator: "\u{1f}") }
    var isValid: Bool {
        [prefixReading, prefixValue, reading, value].allSatisfy { !$0.isEmpty && $0.utf8.count <= 1024 && !$0.contains("\u{1f}") }
            && (1...1_000_000).contains(count) && timestamp.isFinite && timestamp >= 0
    }
}

private struct LearningDocument: Codable {
    var schemaVersion = 1
    var overrides: [ChoiceRecord] = []
    var associations: [AssociationRecord] = []
}

@objc(JFLearningStore)
public final class LearningStore: NSObject {
    private let directory: URL
    private let file: URL
    private let backup: URL
    private let writer = DispatchQueue(label: "Jianfan.LocalLearningWriter", qos: .utility)
    private let lock = NSLock()
    private var document = LearningDocument()
    private var readOnly = false
    private var errorMessage: String?

    @objc(initWithDirectoryURL:) public init(directoryURL: URL) {
        directory = directoryURL
        file = directoryURL.appendingPathComponent("learning-v1.json")
        backup = directoryURL.appendingPathComponent("learning-v1.json.bak")
        super.init()
        guard directoryURL.isFileURL else {
            readOnly = true
            errorMessage = "Learning data requires a local folder."
            return
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            document = try Self.decode(Data(contentsOf: file))
        } catch StoreError.newerVersion {
            readOnly = true
            errorMessage = "Learning data was created by a newer version."
        } catch {
            do {
                document = try Self.decode(Data(contentsOf: backup))
                errorMessage = "Learning data was recovered from its local backup."
            } catch {
                readOnly = true
                errorMessage = "Learning data could not be read. The original files were preserved."
            }
        }
    }

    private enum StoreError: Error { case invalidData, newerVersion }
    private static func decode(_ data: Data) throws -> LearningDocument {
        guard data.count <= 4 * 1024 * 1024,
              let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = header["schemaVersion"] as? Int else { throw StoreError.invalidData }
        guard version == 1 else { throw StoreError.newerVersion }
        let decoded = try JSONDecoder().decode(LearningDocument.self, from: data)
        guard decoded.overrides.count <= 10000, decoded.associations.count <= 2000,
              decoded.overrides.allSatisfy(\.isValid), decoded.associations.allSatisfy(\.isValid) else { throw StoreError.invalidData }
        return decoded
    }

    private func locked<T>(_ action: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return action()
    }

    @objc public var recordCount: Int { locked { document.overrides.count + document.associations.count } }
    @objc public var lastError: String? { locked { errorMessage } }
    @objc(overrideSnapshotJSON) public func overrideJSON() -> Data { locked { (try? JSONEncoder().encode(document.overrides)) ?? Data("[]".utf8) } }

    @objc(replaceOverrideSnapshot:) public func replaceOverrides(json: Data) -> Bool {
        guard json.count <= 4 * 1024 * 1024,
              let records = try? JSONDecoder().decode([ChoiceRecord].self, from: json),
              records.count <= 10000, records.allSatisfy(\.isValid) else { return false }
        return locked {
            guard !readOnly else { return false }
            document.overrides = records
            scheduleWrite()
            return true
        }
    }

    @objc(recordAssociationWithPrefixReading:prefixValue:reading:value:timestamp:) public func recordAssociation(prefixReading: String, prefixValue: String, reading: String, value: String, timestamp: Double) {
        var record = AssociationRecord(prefixReading: prefixReading, prefixValue: prefixValue, reading: reading, value: value, count: 1, timestamp: timestamp)
        guard record.isValid else { return }
        locked {
            guard !readOnly else { return }
            if let index = document.associations.firstIndex(where: { $0.key == record.key }) {
                record.count = min(document.associations[index].count + 1, 1_000_000)
                document.associations[index] = record
            } else {
                document.associations.append(record)
            }
            if document.associations.count > 2000 {
                document.associations.sort { $0.timestamp > $1.timestamp }
                document.associations = Array(document.associations.prefix(2000))
            }
            scheduleWrite()
        }
    }

    @objc(rankAssociationIndicesWithPrefixReading:prefixValue:readings:values:timestamp:) public func rankAssociationIndices(prefixReading: String, prefixValue: String, readings: [String], values: [String], timestamp: Double) -> [NSNumber] {
        guard readings.count == values.count, timestamp.isFinite else { return values.indices.map { NSNumber(value: $0) } }
        let records = locked { document.associations.filter { $0.prefixReading == prefixReading && $0.prefixValue == prefixValue } }
        let scores: [Double] = values.indices.map { index in
            guard let record = records.first(where: { $0.reading == readings[index] && $0.value == values[index] }) else { return 0 }
            return Double(record.count) * exp2(-max(0, timestamp - record.timestamp) / (30 * 86400))
        }
        return values.indices.sorted { left, right in
            if scores[left] == scores[right] { return left < right }
            return scores[left] > scores[right]
        }.map { NSNumber(value: $0) }
    }

    @objc public func clear() {
        locked {
            document = LearningDocument()
            readOnly = false
            errorMessage = nil
            scheduleWrite(resetBackup: true)
        }
    }

    // Called with the lock held. File writes never block the input event handler.
    private func scheduleWrite(resetBackup: Bool = false) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document) else { return }
        writer.async { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if resetBackup {
                    try data.write(to: backup, options: .atomic)
                } else if let oldData = try? Data(contentsOf: file), (try? Self.decode(oldData)) != nil {
                    try oldData.write(to: backup, options: .atomic)
                }
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                if FileManager.default.fileExists(atPath: backup.path) {
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                }
                locked { errorMessage = nil }
            } catch {
                locked { errorMessage = "Learning data could not be saved. Check the local folder permissions." }
            }
        }
    }

    @objc public func flush() { writer.sync {} }
}
