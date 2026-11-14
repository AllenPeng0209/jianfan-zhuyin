import Foundation

struct KeyboardSettings: Codable {
    var learningEnabled = true
    var simplified = true
    var resetToken = ""
    var revision = ""

    static let groupIdentifier = "group.com.allenpeng.jianfan.zhuyin"
    static func sharedDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }
    static func read(from directory: URL) -> KeyboardSettings {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("settings-v1.json")),
              data.count < 65536, let settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return settings
    }
    func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent("settings-v1.json"), options: .atomic)
    }
}
