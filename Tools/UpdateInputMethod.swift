import AppKit
import Carbon
import Foundation

enum UpdateError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): return message } }
}

@MainActor
private enum Updater {
    static func property(_ source: TISInputSource, _ key: CFString) -> Any? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
    static func sources() -> [TISInputSource] {
        TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
    }
    static func id(_ source: TISInputSource) -> String { property(source, kTISPropertyInputSourceID) as? String ?? "" }
    static func wait(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    static func info(_ app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw UpdateError.failed("Invalid application metadata")
        }
        return result
    }
    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.failed(String(decoding: output, as: UTF8.self))
        }
    }

    static func perform() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else { throw UpdateError.failed("Usage: updater <source.app> <backup-folder> [--check-only]") }
        let source = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let backup = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        let destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods/JianfanZhuyin.app")
        let sourceInfo = try info(source)
        let oldInfo = try info(destination)
        guard let bundleID = oldInfo["CFBundleIdentifier"] as? String,
              bundleID == "com.local.inputmethod.JianfanZhuyin",
              sourceInfo["CFBundleIdentifier"] as? String == bundleID,
              let oldVersion = oldInfo["CFBundleVersion"] as? String,
              let newVersion = sourceInfo["CFBundleVersion"] as? String,
              oldVersion.compare(newVersion, options: .numeric) == .orderedAscending else {
            throw UpdateError.failed("The application identity must match and its build number must increase")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", destination.path])
        if arguments.contains("--check-only") { print("Verified matching identities, signatures and an increasing build number"); return }

        let selected = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let previousID = id(selected)
        guard let ascii = sources().first(where: { id($0) == "com.apple.keylayout.ABC" || id($0) == "com.apple.keylayout.US" }),
              TISSelectInputSource(ascii) == noErr else { throw UpdateError.failed("Cannot switch temporarily to the system keyboard") }
        wait(0.3)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in apps { _ = app.terminate() }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { wait(0.1) }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            if let previous = sources().first(where: { id($0) == previousID }) { _ = TISSelectInputSource(previous) }
            throw UpdateError.failed("The input method is still busy; no files were replaced")
        }

        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let oldAppBackup = backup.appendingPathComponent("JianfanZhuyin.app")
        try FileManager.default.copyItem(at: destination, to: oldAppBackup)
        let preferences = UserDefaults(suiteName: bundleID)?.persistentDomain(forName: bundleID) ?? [:]
        let prefData = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
        let prefURL = backup.appendingPathComponent("preferences.plist")
        try prefData.write(to: prefURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: prefURL.path)
        let custom = preferences["UseCustomUserPhraseLocation"] as? Bool ?? false
        let customPath = preferences["CustomUserPhraseLocation"] as? String ?? ""
        let dataDirectory = custom && !customPath.isEmpty
            ? URL(fileURLWithPath: customPath)
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/JianfanZhuyin")
        let dataBackup = backup.appendingPathComponent("UserData")
        try FileManager.default.createDirectory(at: dataBackup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let names = ["data.txt", "data-plain-bpmf.txt", "exclude-phrases.txt", "exclude-phrases-plain-bpmf.txt", "phrases-replacement.txt", "learning-v1.json"]
        var copied = 0
        for name in names + names.map({ $0 + ".bak" }) {
            let file = dataDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.copyItem(at: file, to: dataBackup.appendingPathComponent(name))
                copied += 1
            }
        }

        do {
            try run("/usr/bin/ditto", [source.path, destination.path])
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", destination.path])
            guard try info(destination)["CFBundleVersion"] as? String == newVersion else { throw UpdateError.failed("The installed build does not match the update") }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: oldAppBackup, to: destination)
            if let previous = sources().first(where: { id($0) == previousID }) { _ = TISSelectInputSource(previous) }
            throw error
        }
        let registration = TISRegisterInputSource(destination as CFURL)
        for input in sources() where property(input, kTISPropertyBundleID) as? String == bundleID {
            if property(input, kTISPropertyInputSourceIsEnabled) as? Bool != true { _ = TISEnableInputSource(input) }
        }
        wait(0.3)
        var activation: OSStatus = noErr
        if previousID.hasPrefix(bundleID),
           let ownMode = sources().first(where: {
               property($0, kTISPropertyBundleID) as? String == bundleID &&
               property($0, kTISPropertyInputSourceIsSelectCapable) as? Bool == true
           }) {
            activation = TISSelectInputSource(ownMode)
        } else if let previous = sources().first(where: { id($0) == previousID }) {
            activation = TISSelectInputSource(previous)
        }
        wait(1)
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            let process = Process()
            let executable = sourceInfo["CFBundleExecutable"] as? String ?? "JianfanZhuyin"
            process.executableURL = destination.appendingPathComponent("Contents/MacOS/" + executable)
            let log = backup.appendingPathComponent("new-runtime.log")
            _ = FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = handle
            process.standardError = handle
            try process.run()
            wait(1)
            try handle.close()
        }
        let report: [String: Any] = [
            "oldBuild": oldVersion, "newBuild": newVersion,
            "version": sourceInfo["CFBundleShortVersionString"] as? String ?? "",
            "backupPath": backup.path, "dataFilesBackedUp": copied,
            "registrationStatus": registration, "selectionStatus": activation,
            "selectedSource": id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()),
            "runningPIDs": NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map { $0.processIdentifier },
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try reportData.write(to: backup.appendingPathComponent("UPDATE_RESULT.json"), options: .atomic)
        print(String(decoding: reportData, as: UTF8.self))
    }
}

@main
private struct UpdateMain {
    @MainActor static func main() {
        do { try Updater.perform() }
        catch { fputs("Update failed: \(error)\n", stderr); exit(1) }
    }
}
