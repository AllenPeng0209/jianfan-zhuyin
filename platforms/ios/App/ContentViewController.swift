import UIKit
import UniformTypeIdentifiers
import JianfanUserData

@MainActor
final class ContentViewController: UITableViewController {
    private var settings = KeyboardSettings()
    private var shared: URL?
    private var engine: JFCoreEngine?
    private var store: UserLexiconStore?
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("簡繁注音")
        navigationController?.navigationBar.prefersLargeTitles = true
        shared = KeyboardSettings.sharedDirectory()
        if let shared { settings = KeyboardSettings.read(from: shared) }
        do {
            let engine = try JFCoreEngine(resourceDirectory: Bundle.main.resourceURL!.appendingPathComponent("Dictionaries").path)
            self.engine = engine
            if let shared { store = UserLexiconStore(fileURL: shared.appendingPathComponent("user-phrases.txt"), readingValidator: { engine.supportsReading($0) }) }
        } catch { showError(error) }
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [2,1,3,2][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        [L("開始使用"),L("個人詞庫"),L("輸入偏好"),L("關於")][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return L("在「設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤」加入簡繁注音，再以地球鍵切換。不需要開啟完整取用。")
        case 1: return shared == nil ? L("共享詞庫無法使用。請確認正式簽署版本已安裝。") : L("新增專有名詞、修改讀音，或匯入其他平台匯出的 JSON 詞庫。")
        case 2: return L("選字記憶保存在鍵盤自己的本機空間。清除指令會在下次開啟鍵盤時生效；個人詞庫會保留。")
        default: return L("不傳送輸入內容、不追蹤、不需要網路。")
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let titles = [[L("開啟系統設定"),L("體驗鍵盤")],[L("管理詞庫")],[L("預設簡體輸出"),L("長期選字記憶"),L("清除鍵盤記憶")],[L("隱私與使用說明"),L("開源授權")]]
        cell.textLabel?.text = titles[indexPath.section][indexPath.row]
        cell.accessibilityIdentifier = "home-\(indexPath.section)-\(indexPath.row)"
        if indexPath.section == 2 && indexPath.row < 2 {
            let toggle = UISwitch(); toggle.isOn = indexPath.row == 0 ? settings.simplified : settings.learningEnabled
            toggle.accessibilityLabel = cell.textLabel?.text
            toggle.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                if indexPath.row == 0 { settings.simplified = toggle.isOn } else { settings.learningEnabled = toggle.isOn }
                saveSettings()
            }, for: .valueChanged)
            cell.accessoryView = toggle; cell.selectionStyle = .none
        } else { cell.accessoryType = .disclosureIndicator }
        if indexPath.section == 1 { cell.detailTextLabel?.text = String((try? store?.entries().count) ?? 0) }
        if indexPath.section == 2 && indexPath.row == 2 { cell.textLabel?.textColor = .systemRed }
        return cell
    }
    private func saveSettings() {
        guard let shared else { return }
        settings.revision = UUID().uuidString
        do { try settings.write(to: shared) } catch { showError(error) }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section,indexPath.row) {
        case (0,0): if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case (0,1): navigationController?.pushViewController(DemoViewController(), animated: true)
        case (1,0):
            if let store, let engine { navigationController?.pushViewController(LexiconViewController(store: store,engine: engine), animated: true) }
        case (2,2):
            let alert = UIAlertController(title: L("清除鍵盤記憶？"), message: L("下次開啟鍵盤時會清除選字與聯想排序紀錄，個人詞庫會保留。"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L("取消"), style: .cancel))
            alert.addAction(UIAlertAction(title: L("清除"), style: .destructive) { [weak self] _ in
                self?.settings.resetToken = UUID().uuidString; self?.saveSettings()
            })
            present(alert, animated: true)
        case (3,0):
            showText(L("隱私與使用說明"), L("簡繁注音完全離線運作，不收集、不上傳輸入內容，也沒有廣告或分析服務。\n\n鍵盤不要求完整取用。個人詞庫由主程式管理，鍵盤讀取；選字及聯想記憶留在鍵盤自己的本機空間。\n\n注音未完成時顯示在鍵盤組字列，按聲調或一聲完成音節；點候選更換選字，按確認或空白送出文字。聯想鍵提供接續詞。\n\niOS 在密碼、部分電話欄位或不允許第三方鍵盤的應用中，會使用系統鍵盤。\n\n來源：https://github.com/AllenPeng0209/jianfan-zhuyin"))
        case (3,1):
            let url = Bundle.main.resourceURL!.appendingPathComponent("Dictionaries/ThirdPartyNotices.txt")
            showText(L("開源授權"), (try? String(contentsOf: url,encoding: .utf8)) ?? "")
        default: break
        }
    }
    private func showText(_ title: String,_ text: String) {
        let controller = UIViewController(); controller.title = title
        let view = UITextView(); view.text = text; view.isEditable = false; view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true; view.textContainerInset = UIEdgeInsets(top: 20,left: 18,bottom: 20,right: 18)
        controller.view = view; navigationController?.pushViewController(controller, animated: true)
    }
}

extension UIViewController {
    func showError(_ error: Error) {
        let alert = UIAlertController(title: L("無法完成操作"), message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("好"), style: .default))
        present(alert, animated: true)
    }
}

@MainActor
final class DemoViewController: UIViewController {
    private var model: KeyboardModel?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("體驗鍵盤"); view.backgroundColor = .systemBackground
        do {
            let engine = try JFCoreEngine(resourceDirectory: Bundle.main.resourceURL!.appendingPathComponent("Dictionaries").path)
            let directory = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("DemoLearning")
            let shared = KeyboardSettings.sharedDirectory()
            let model = KeyboardModel(engine: engine, learningDirectory: directory, phrasesURL: shared?.appendingPathComponent("user-phrases.txt"))
            if let shared { model.apply(KeyboardSettings.read(from: shared)) }
            self.model = model
            let text = UITextView(); text.isEditable = false; text.font = .preferredFont(forTextStyle: .title2)
            text.accessibilityIdentifier = "demo-output"
            text.textContainerInset = UIEdgeInsets(top: 16,left: 16,bottom: 16,right: 16)
            let hint = UILabel(); hint.text = L("用下方鍵盤試打，按確認送出文字。")
            hint.font = .preferredFont(forTextStyle: .subheadline); hint.textColor = .secondaryLabel; hint.numberOfLines = 0
            let keyboard = ZhuyinKeyboardView(model: model); keyboard.needsGlobe = false
            model.insertText = { [weak text] in text?.text += $0 }
            model.deleteText = { [weak text] in if let text, !text.text.isEmpty { text.text.removeLast() } }
            let stack = UIStackView(arrangedSubviews: [hint,text,keyboard]); stack.axis = .vertical; stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,constant: 12), stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                keyboard.heightAnchor.constraint(equalToConstant: 334)
            ])
        } catch { showError(error) }
    }
    override func viewWillDisappear(_ animated: Bool) { model?.flush(); super.viewWillDisappear(animated) }
}
