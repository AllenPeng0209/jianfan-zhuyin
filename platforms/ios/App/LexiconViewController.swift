import UIKit
import UniformTypeIdentifiers
import JianfanUserData

@MainActor
final class LexiconViewController: UITableViewController, UISearchResultsUpdating, UIDocumentPickerDelegate {
    private let store: UserLexiconStore
    private let engine: JFCoreEngine
    private let search = UISearchController(searchResultsController: nil)
    private var entries: [UserPhrase] = []
    private var filtered: [UserPhrase] = []
    init(store: UserLexiconStore,engine: JFCoreEngine) { self.store = store; self.engine = engine; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = L("個人詞庫")
        search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = L("搜尋詞語或注音"); navigationItem.searchController = search
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add,target: self,action: #selector(add)),
            UIBarButtonItem(title: L("匯入"),style: .plain,target: self,action: #selector(importFile)),
            UIBarButtonItem(title: L("匯出"),style: .plain,target: self,action: #selector(exportFile))
        ]
        navigationItem.rightBarButtonItems?.first?.accessibilityIdentifier = "add-phrase"
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }
    private func reload() {
        do { entries = try store.entries(); updateSearchResults(for: search) } catch { showError(error) }
    }
    func updateSearchResults(for searchController: UISearchController) {
        let query = search.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        filtered = entries.filter { query.isEmpty || $0.phrase.localizedCaseInsensitiveContains(query) || $0.reading.contains(query) }
        tableView.reloadData()
        if filtered.isEmpty {
            let label = UILabel(); label.text = query.isEmpty ? L("還沒有個人詞語，按 + 新增。") : L("沒有符合的詞語。")
            label.textAlignment = .center; label.textColor = .secondaryLabel; label.numberOfLines = 0; tableView.backgroundView = label
        } else { tableView.backgroundView = nil }
    }
    override func tableView(_ tableView: UITableView,numberOfRowsInSection section: Int) -> Int { filtered.count }
    override func tableView(_ tableView: UITableView,cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle,reuseIdentifier: nil)
        cell.textLabel?.text = filtered[indexPath.row].phrase; cell.detailTextLabel?.text = filtered[indexPath.row].reading
        cell.textLabel?.font = .preferredFont(forTextStyle: .title3); cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView,didSelectRowAt indexPath: IndexPath) { edit(filtered[indexPath.row]) }
    override func tableView(_ tableView: UITableView,commit editingStyle: UITableViewCell.EditingStyle,forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        do { try store.remove(filtered[indexPath.row]); reload() } catch { showError(error) }
    }
    @objc private func add() { edit(nil) }
    private func edit(_ phrase: UserPhrase?) {
        navigationController?.pushViewController(PhraseEditorViewController(store: store,engine: engine,original: phrase), animated: true)
    }
    @objc private func importFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json],asCopy: true)
        picker.delegate = self; present(picker,animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController,didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do { _ = try store.importJSON(Data(contentsOf: url)); reload() } catch { showError(error) }
    }
    @objc private func exportFile() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Jianfan-phrases-" + UUID().uuidString + ".json")
            try store.exportJSON().write(to: url,options: .atomic)
            let controller = UIActivityViewController(activityItems: [url],applicationActivities: nil)
            controller.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
            present(controller,animated: true)
        } catch { showError(error) }
    }
}

@MainActor
final class PhraseEditorViewController: UIViewController {
    private let store: UserLexiconStore
    private let engine: JFCoreEngine
    private let original: UserPhrase?
    private let word = UITextField()
    private let reading = UITextField()
    init(store: UserLexiconStore,engine: JFCoreEngine,original: UserPhrase?) {
        self.store = store; self.engine = engine; self.original = original; super.init(nibName: nil,bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = original == nil ? L("新增詞語") : L("編輯詞語"); view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: L("儲存"),style: .done,target: self,action: #selector(save))
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "save-phrase"
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        word.text = original?.phrase; reading.text = original?.reading
        word.placeholder = L("詞語"); reading.placeholder = L("注音，以 - 或空格分隔音節")
        word.accessibilityIdentifier = "phrase-word"; reading.accessibilityIdentifier = "phrase-reading"
        for field in [word,reading] {
            field.borderStyle = .roundedRect; field.font = .preferredFont(forTextStyle: .title3)
            field.autocorrectionType = .no; field.autocapitalizationType = .none
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true; stack.addArrangedSubview(field)
        }
        let auto = UIButton(type: .system); auto.setTitle(L("自動填入讀音"),for: .normal)
        auto.accessibilityIdentifier = "auto-reading"
        auto.addAction(UIAction { [weak self] _ in guard let self else { return }; reading.text = engine.suggestedReading(word.text ?? "") }, for: .touchUpInside)
        stack.addArrangedSubview(auto)
        let hint = UILabel(); hint.text = L("最多 8 個注音音節，可用短讀音展開較長的詞語。多音字請確認讀音後儲存。")
        hint.font = .preferredFont(forTextStyle: .subheadline); hint.textColor = .secondaryLabel; hint.numberOfLines = 0; stack.addArrangedSubview(hint)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,constant: 20),stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,constant: 24)
        ])
    }
    @objc private func save() {
        do {
            let row = UserPhrase(phrase: engine.toTraditional(word.text ?? ""),reading: reading.text ?? "")
            try store.upsert(row,replacing: original); navigationController?.popViewController(animated: true)
        } catch { showError(error) }
    }
}
