import UIKit

final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel?
    private var keyboard: ZhuyinKeyboardView?
    private var height: NSLayoutConstraint?
    override func viewDidLoad() {
        super.viewDidLoad()
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("KeyboardLearning", isDirectory: true)
            let engine = try JFCoreEngine(resourceDirectory: Bundle.main.resourceURL!.appendingPathComponent("Dictionaries").path)
            let shared = KeyboardSettings.sharedDirectory()
            let model = KeyboardModel(engine: engine, learningDirectory: directory,
                                      phrasesURL: shared?.appendingPathComponent("user-phrases.txt"))
            model.insertText = { [weak self] in self?.textDocumentProxy.insertText($0) }
            model.deleteText = { [weak self] in self?.textDocumentProxy.deleteBackward() }
            if let shared { model.apply(KeyboardSettings.read(from: shared)) }
            self.model = model
            let keyboard = ZhuyinKeyboardView(model: model)
            keyboard.needsGlobe = needsInputModeSwitchKey
            keyboard.nextKeyboard = { [weak self] button,event in
                if let event { self?.handleInputModeList(from: button, with: event) }
                else { self?.advanceToNextInputMode() }
            }
            keyboard.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(keyboard)
            NSLayoutConstraint.activate([
                keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                keyboard.topAnchor.constraint(equalTo: view.topAnchor),keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            height = view.heightAnchor.constraint(equalToConstant: 334)
            height?.priority = .init(999); height?.isActive = true
            self.keyboard = keyboard
        } catch {
            let stack = UIStackView(); stack.axis = .vertical; stack.frame = view.bounds; stack.autoresizingMask = [.flexibleWidth,.flexibleHeight]
            let label = UILabel(); label.text = L("詞庫無法載入，請重新安裝簡繁注音。")
            label.numberOfLines = 0; label.textAlignment = .center; stack.addArrangedSubview(label)
            let next = UIButton(type: .system); next.setTitle(L("下一個鍵盤"), for: .normal)
            next.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            stack.addArrangedSubview(next); view.addSubview(stack)
        }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let shared = KeyboardSettings.sharedDirectory() {
            model?.apply(KeyboardSettings.read(from: shared))
            model?.engine.reloadUserPhrases(shared.appendingPathComponent("user-phrases.txt").path, excluded: "")
        }
        keyboard?.needsGlobe = needsInputModeSwitchKey
        keyboard?.render()
    }
    override func viewWillDisappear(_ animated: Bool) {
        model?.flush()
        super.viewWillDisappear(animated)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        height?.constant = view.bounds.width > 600 ? 290 : 334
    }
    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        // Keep preedit inside the keyboard; changing host fields never submits it.
        if let model, !model.engine.composition.isEmpty { _ = model.engine.commit(); keyboard?.render() }
    }
}
