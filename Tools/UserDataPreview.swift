import AppKit
import JianfanUserData

@MainActor
private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var controller: UserPhraseWindowController?
    private var enabled = true
    private var memory: LearningStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JianfanPreview-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("data.txt")
            let lexicon = UserLexiconStore(fileURL: file)
            try lexicon.upsert(UserPhrase(phrase: "星河計畫", reading: "ㄒㄧㄥ-ㄏㄜˊ-ㄐㄧˋ-ㄏㄨㄚˋ"))
            try lexicon.upsert(UserPhrase(phrase: "研討", reading: "ㄧㄢˊ-ㄊㄠˇ"))
            let memory = LearningStore(directoryURL: directory)
            self.memory = memory
            memory.recordAssociation(prefixReading: "ㄒㄧㄥ-ㄏㄜˊ", prefixValue: "星河", reading: "ㄒㄧㄥ-ㄏㄜˊ-ㄐㄧˋ-ㄏㄨㄚˋ", value: "星河計畫", timestamp: Date().timeIntervalSince1970)
            memory.flush()
            let readings = ["離線測試": "ㄌㄧˊ-ㄒㄧㄢˋ-ㄘㄜˋ-ㄕˋ", "星河計畫": "ㄒㄧㄥ-ㄏㄜˊ-ㄐㄧˋ-ㄏㄨㄚˋ", "研究": "ㄧㄢˊ-ㄐㄧㄡˋ"]
            let controls = LearningControls(isEnabled: { [weak self] in self?.enabled ?? false },
                setEnabled: { [weak self] in self?.enabled = $0 },
                recordCount: { memory.recordCount }, lastError: { memory.lastError }, clear: { memory.clear(); memory.flush() })
            controller = UserPhraseWindowController(fileURL: file, canonicalize: { $0 }, displayPhrase: { $0 },
                suggestReading: { readings[$0] }, didSave: {}, learning: controls)
            controller?.showAndActivate()
            if let index = CommandLine.arguments.firstIndex(of: "--render"),
               CommandLine.arguments.indices.contains(index + 1),
               let view = controller?.window?.contentView {
                let appearance = NSAppearance(named: .aqua)!
                controller?.window?.appearance = appearance
                var rendered: Data?
                appearance.performAsCurrentDrawingAppearance {
                    view.wantsLayer = true
                    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                    view.layoutSubtreeIfNeeded()
                    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        rendered = bitmap.representation(using: .png, properties: [:])
                    }
                }
                if let rendered { try rendered.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic) }
                NSApp.terminate(nil)
            }
        } catch { NSLog("Preview could not open: %@", error.localizedDescription) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
private struct PreviewMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = PreviewDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
