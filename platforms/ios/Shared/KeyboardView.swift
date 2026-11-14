import UIKit

func L(_ text: String) -> String { NSLocalizedString(text, comment: "") }

@MainActor
final class ZhuyinKeyboardView: UIView {
    private let model: KeyboardModel
    private let root = UIStackView()
    private let preedit = UILabel()
    private let candidateStack = UIStackView()
    private let candidateScroll = UIScrollView()
    private let keyRows = UIStackView()
    private let script = UIButton(type: .system)
    private let mode = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let globe = UIButton(type: .system)
    private var latin = false
    private var capitals = false
    private var symbols = false
    var nextKeyboard: ((UIButton, UIEvent?) -> Void)?
    var needsGlobe = true { didSet { globe.isHidden = !needsGlobe } }
    private let rows: [[(String,String)]] = [
        Array(zip(["1","2","3","4","5","6","7","8","9","0","-"], ["ㄅ","ㄉ","ˇ","ˋ","ㄓ","ˊ","˙","ㄚ","ㄞ","ㄢ","ㄦ"])),
        Array(zip(Array("qwertyuiop").map(String.init), ["ㄆ","ㄊ","ㄍ","ㄐ","ㄔ","ㄗ","ㄧ","ㄛ","ㄟ","ㄣ"])),
        Array(zip(Array("asdfghjkl;").map(String.init), ["ㄇ","ㄋ","ㄎ","ㄑ","ㄕ","ㄘ","ㄨ","ㄜ","ㄠ","ㄤ"])),
        Array(zip(Array("zxcvbnm,./").map(String.init), ["ㄈ","ㄌ","ㄏ","ㄒ","ㄖ","ㄙ","ㄩ","ㄝ","ㄡ","ㄥ"]))
    ]

    init(model: KeyboardModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        root.axis = .vertical
        root.spacing = 5
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            root.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4)
        ])
        let compositionRow = UIStackView()
        compositionRow.spacing = 8
        preedit.font = .systemFont(ofSize: 21)
        preedit.adjustsFontSizeToFitWidth = true
        preedit.minimumScaleFactor = 0.7
        preedit.accessibilityIdentifier = "preedit"
        preedit.lineBreakMode = .byTruncatingHead
        compositionRow.addArrangedSubview(preedit)
        let association = control(L("聯想")) { [weak self] in self?.model.showAssociations(); self?.render() }
        association.accessibilityIdentifier = "associations"
        association.widthAnchor.constraint(equalToConstant: 52).isActive = true
        compositionRow.addArrangedSubview(association)
        script.setTitle(L("簡"), for: .normal)
        script.accessibilityIdentifier = "toggle-script"
        script.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if latin { capitals.toggle(); buildKeys() } else { model.toggleScript() }
            render()
        }, for: .touchUpInside)
        script.widthAnchor.constraint(equalToConstant: 36).isActive = true
        compositionRow.addArrangedSubview(script)
        root.addArrangedSubview(compositionRow)
        compositionRow.heightAnchor.constraint(equalToConstant: 34).isActive = true
        candidateStack.axis = .horizontal
        candidateStack.spacing = 4
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateScroll.addSubview(candidateStack)
        candidateScroll.showsHorizontalScrollIndicator = false
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidateStack.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor)
        ])
        root.addArrangedSubview(candidateScroll)
        candidateScroll.heightAnchor.constraint(equalToConstant: 42).isActive = true
        keyRows.axis = .vertical
        keyRows.spacing = 6
        keyRows.distribution = .fillEqually
        root.addArrangedSubview(keyRows)
        let bottom = UIStackView()
        bottom.spacing = 5
        mode.setTitle("ABC", for: .normal)
        mode.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if !model.engine.composition.isEmpty { model.enter() }
            latin.toggle(); symbols = false; buildKeys(); render()
        }, for: .touchUpInside)
        mode.accessibilityIdentifier = "toggle-latin"
        bottom.addArrangedSubview(mode)
        mode.widthAnchor.constraint(equalToConstant: 44).isActive = true
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.accessibilityLabel = L("下一個鍵盤")
        globe.addTarget(self, action: #selector(nextMode(_:event:)), for: .allTouchEvents)
        globe.widthAnchor.constraint(equalToConstant: 36).isActive = true
        bottom.addArrangedSubview(globe)
        let punctuation = control("，。") { [weak self] in
            guard let self else { return }; symbols.toggle(); buildKeys(); render()
        }
        punctuation.widthAnchor.constraint(equalToConstant: 40).isActive = true
        bottom.addArrangedSubview(punctuation)
        style(spaceButton)
        spaceButton.accessibilityIdentifier = "space"
        spaceButton.addAction(UIAction { [weak self] _ in self?.model.space(); self?.render() }, for: .touchUpInside)
        bottom.addArrangedSubview(spaceButton)
        let delete = control("⌫") { [weak self] in self?.model.backspace(); self?.render() }
        delete.accessibilityLabel = L("刪除")
        delete.accessibilityIdentifier = "backspace"
        delete.widthAnchor.constraint(equalToConstant: 42).isActive = true
        bottom.addArrangedSubview(delete)
        let enter = control(L("確認")) { [weak self] in self?.model.enter(); self?.render() }
        enter.accessibilityIdentifier = "commit"
        enter.widthAnchor.constraint(equalToConstant: 48).isActive = true
        bottom.addArrangedSubview(enter)
        root.addArrangedSubview(bottom)
        bottom.heightAnchor.constraint(equalToConstant: 42).isActive = true
        buildKeys()
        render()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func nextMode(_ sender: UIButton, event: UIEvent?) { nextKeyboard?(sender,event) }
    private func style(_ button: UIButton) {
        button.backgroundColor = .tertiarySystemBackground
        button.tintColor = .label
        button.layer.cornerRadius = 6
        button.titleLabel?.font = .systemFont(ofSize: 20)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.65
    }
    private func control(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        style(button)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
    private func buildKeys() {
        keyRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let symbolRows = [Array("，。？！；：「」『』"), Array("、（）《》〈〉【】"), Array("1234567890"), Array("+-=*/@#%&_")]
        for (rowIndex,row) in rows.enumerated() {
            let stack = UIStackView()
            stack.axis = .horizontal; stack.spacing = 4; stack.distribution = .fillEqually
            for (column,(key,label)) in row.enumerated() {
                if symbols && column >= symbolRows[rowIndex].count { continue }
                let title = symbols ? String(symbolRows[rowIndex][column]) : (latin ? (capitals ? key.uppercased() : key) : label)
                let button = control(title) { [weak self] in
                    guard let self else { return }
                    if symbols || latin {
                        if !model.engine.composition.isEmpty { model.enter() }
                        model.insertText(symbols ? title : (capitals ? key.uppercased() : key))
                    } else { model.press(key) }
                    render()
                }
                button.accessibilityIdentifier = "key-" + key
                button.accessibilityLabel = title
                stack.addArrangedSubview(button)
            }
            keyRows.addArrangedSubview(stack)
        }
    }
    func render() {
        preedit.text = model.engine.composition.isEmpty ? L("標準注音 · 離線") : model.engine.composition
        preedit.textColor = model.engine.composition.isEmpty ? .secondaryLabel : .label
        script.setTitle(latin ? "⇧" : (model.engine.simplified ? L("簡") : L("繁")), for: .normal)
        script.accessibilityLabel = latin ? (capitals ? L("小寫") : L("大寫")) : (model.engine.simplified ? L("切換為繁體") : L("切換為簡體"))
        mode.setTitle(latin ? "ㄅㄆㄇ" : "ABC", for: .normal)
        spaceButton.setTitle(!model.engine.phonetic.isEmpty && !latin && !symbols ? L("一聲") : L("空白"), for: .normal)
        candidateStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index,candidate) in model.candidates.prefix(100).enumerated() {
            let button = control(candidate.value) { [weak self] in self?.model.choose(index); self?.render() }
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
            button.accessibilityIdentifier = "candidate-\(index)"
            button.accessibilityLabel = candidate.value + ", " + candidate.reading
            candidateStack.addArrangedSubview(button)
        }
        candidateScroll.setContentOffset(.zero, animated: false)
    }
}
