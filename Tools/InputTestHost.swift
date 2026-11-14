import AppKit

// Developer-only native client for exercising the installed input method.
@MainActor
final class InputTestDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 760, height: 460)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "简繁注音 实机输入测试"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: rect)
        window.contentView = content

        let label = NSTextField(labelWithString: "请选择简繁注音，并在下方逐键输入 su3cl3 或 gj bj4。")
        label.frame = NSRect(x: 24, y: 414, width: 710, height: 24)
        content.addSubview(label)

        let settings = NSButton(title: "打开键盘设置", target: self, action: #selector(openKeyboardSettings))
        settings.frame = NSRect(x: 24, y: 365, width: 150, height: 32)
        content.addSubview(settings)

        let scroll = NSScrollView(frame: NSRect(x: 24, y: 24, width: 712, height: 324))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let editor = NSTextView(frame: scroll.bounds)
        editor.isRichText = false
        editor.font = .systemFont(ofSize: 24)
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.autoresizingMask = [.width, .height]
        scroll.documentView = editor
        content.addSubview(scroll)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openKeyboardSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct InputTestMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = InputTestDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
