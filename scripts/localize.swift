import Foundation

// Build-time localization of the upstream UI; the input engine uses OpenCC.
let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fatalError("Usage: localize.swift <source-root> <input-method-app> <installer-app>")
}
let sourceRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
let inputApp = URL(fileURLWithPath: arguments[2], isDirectory: true)
let installerApp = URL(fileURLWithPath: arguments[3], isDirectory: true)
let fileManager = FileManager.default

func localizedText(_ text: String) -> String {
    let converted = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
    return converted.replacingOccurrences(of: "小麦注音", with: "简繁注音")
}

func addLocalization(from source: URL, to app: URL) throws {
    let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
    let destination = resources.appendingPathComponent("zh-Hans.lproj", isDirectory: true)
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    let files = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
    for file in files where ["strings", "stringsdict", "txt"].contains(file.pathExtension) {
        let text = try String(contentsOf: file, encoding: .utf8)
        try localizedText(text).write(to: destination.appendingPathComponent(file.lastPathComponent), atomically: true, encoding: .utf8)
    }
    let nibSource = source.appendingPathComponent("MainMenu.xib")
    if fileManager.fileExists(atPath: nibSource.path) {
        let temporary = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporary) }
        let translated = temporary.appendingPathComponent("MainMenu.xib")
        try localizedText(String(contentsOf: nibSource, encoding: .utf8)).write(to: translated, atomically: true, encoding: .utf8)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["ibtool", "--compile", destination.appendingPathComponent("MainMenu.nib").path, translated.path]
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 { throw NSError(domain: "JianfanBuild", code: Int(task.terminationStatus)) }
    }
}

try addLocalization(from: sourceRoot.appendingPathComponent("Source/zh-Hant.lproj"), to: inputApp)
try addLocalization(from: sourceRoot.appendingPathComponent("Source/Installer/zh-Hant.lproj"), to: installerApp)
let vendorRoot = sourceRoot.deletingLastPathComponent()
let noticeFiles = [
    sourceRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("licenses/libtabe-COPYING"),
    sourceRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("licenses/libtabe-tsi-COPYING"),
    sourceRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("licenses/darts-clone-COPYING.md"),
    sourceRoot.appendingPathComponent("LICENSE.txt"),
    sourceRoot.appendingPathComponent("ACKNOWLEDGEMENTS.md"),
    vendorRoot.appendingPathComponent("Dependencies/SwiftyOpenCC/LICENSE"),
    vendorRoot.appendingPathComponent("Dependencies/SwiftyOpenCC/OpenCC/LICENSE"),
    vendorRoot.appendingPathComponent("Dependencies/SwiftyOpenCC/OpenCC/deps/marisa-0.2.6/COPYING.md"),
    vendorRoot.appendingPathComponent("Dependencies/SQLite.swift/LICENSE.txt"),
]
var notices = "Jianfan Zhuyin is derived from McBopomofo.\n\n"
for file in noticeFiles {
    notices += "\n" + file.lastPathComponent + "\n\n" + (try String(contentsOf: file, encoding: .utf8)) + "\n"
}
for app in [inputApp, installerApp] {
    try notices.write(to: app.appendingPathComponent("Contents/Resources/ThirdPartyNotices.txt"), atomically: true, encoding: .utf8)
}
let embedded = installerApp.appendingPathComponent("Contents/Resources/JianfanZhuyin.app", isDirectory: true)
if fileManager.fileExists(atPath: embedded.path) { try fileManager.removeItem(at: embedded) }
try fileManager.copyItem(at: inputApp, to: embedded)
print("Added Simplified Chinese UI resources and refreshed the installer payload")
