#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers

private func local(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

@MainActor
public struct LearningControls {
    public var isEnabled: () -> Bool
    public var setEnabled: (Bool) -> Void
    public var recordCount: () -> Int
    public var lastError: () -> String?
    public var clear: () -> Void
    public init(isEnabled: @escaping () -> Bool, setEnabled: @escaping (Bool) -> Void,
                recordCount: @escaping () -> Int, lastError: @escaping () -> String?,
                clear: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.setEnabled = setEnabled
        self.recordCount = recordCount
        self.lastError = lastError
        self.clear = clear
    }
}

@MainActor
public final class UserPhraseWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let store: UserLexiconStore
    private let canonicalize: (String) -> String
    private let displayPhrase: (String) -> String
    private let suggestReading: (String) -> String?
    private let readingSupported: (String) -> Bool
    private let didSave: () -> Void
    private let learning: LearningControls
    private let table = NSTableView()
    private let search = NSSearchField()
    private let phraseField = NSTextField()
    private let readingField = NSTextField()
    private let saveButton = NSButton()
    private let deleteButton = NSButton()
    private let learningToggle = NSButton()
    private let learningStatus = NSTextField(labelWithString: "")
    private let wordCount = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private var entries: [UserPhrase] = []
    private var visible: [UserPhrase] = []
    private var editing: UserPhrase?
    private var reloading = false

    public init(fileURL: URL, canonicalize: @escaping (String) -> String,
                displayPhrase: @escaping (String) -> String, suggestReading: @escaping (String) -> String?,
                readingSupported: @escaping (String) -> Bool = { _ in true },
                didSave: @escaping () -> Void, learning: LearningControls) {
        store = UserLexiconStore(fileURL: fileURL, readingValidator: readingSupported)
        self.canonicalize = canonicalize
        self.displayPhrase = displayPhrase
        self.suggestReading = suggestReading
        self.readingSupported = readingSupported
        self.didSave = didSave
        self.learning = learning
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = local("Personal Phrases and Learning")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 790, height: 530)
        super.init(window: window)
        window.delegate = self
        buildInterface()
        reloadFromDisk()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let result = NSButton(title: local(title), target: self, action: action)
        result.bezelStyle = .rounded
        return result
    }

    private func label(_ title: String, size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
        let result = NSTextField(labelWithString: local(title))
        result.font = .systemFont(ofSize: size)
        result.textColor = secondary ? .secondaryLabelColor : .labelColor
        return result
    }

    private func stack(_ views: [NSView], horizontal: Bool = false, spacing: CGFloat = 12) -> NSStackView {
        let result = NSStackView(views: views)
        result.orientation = horizontal ? .horizontal : .vertical
        result.alignment = horizontal ? .centerY : .leading
        result.distribution = .fill
        result.spacing = spacing
        return result
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        let title = label("Personal Phrases", size: 20)
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let top = stack([title, spacer, button("Import Phrases", #selector(importPhrases)), button("Export Phrases", #selector(exportPhrases))], horizontal: true)
        search.placeholderString = local("Search words or Bopomofo")
        search.delegate = self
        let add = button("New Word", #selector(newWord))
        add.keyEquivalent = "n"
        add.keyEquivalentModifierMask = .command
        let searchRow = stack([search, add], horizontal: true)
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)

        table.delegate = self
        table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 32
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.setAccessibilityLabel(local("Personal phrase list"))
        for (identifier, title, width) in [("phrase", "Word", 165.0), ("reading", "Bopomofo", 270.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = local(title)
            column.width = width
            column.minWidth = 100
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table

        phraseField.delegate = self
        readingField.delegate = self
        phraseField.placeholderString = local("For example: a project or person's name")
        readingField.placeholderString = "ㄒㄧㄥ ㄏㄜˊ"
        phraseField.setAccessibilityLabel(local("Word"))
        readingField.setAccessibilityLabel(local("Bopomofo"))
        let autoReading = button("Suggest Reading", #selector(fillReading))
        saveButton.title = local("Save Word")
        saveButton.target = self
        saveButton.action = #selector(saveWord)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.keyEquivalentModifierMask = []
        deleteButton.title = local("Delete Word")
        deleteButton.target = self
        deleteButton.action = #selector(deleteWord)
        deleteButton.bezelStyle = .rounded
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        let readingHint = NSTextField(wrappingLabelWithString: local("Separate syllables with spaces. Check words with multiple readings."))
        readingHint.font = .systemFont(ofSize: 12)
        readingHint.textColor = .secondaryLabelColor
        readingHint.widthAnchor.constraint(equalToConstant: 280).isActive = true
        let editor = stack([
            label("Word"), phraseField, label("Bopomofo"), readingField, autoReading,
            readingHint,
            stack([saveButton, deleteButton], horizontal: true), message,
        ], spacing: 10)
        editor.widthAnchor.constraint(equalToConstant: 280).isActive = true
        for field in [phraseField, readingField] { field.widthAnchor.constraint(equalTo: editor.widthAnchor).isActive = true }
        let separator = NSBox()
        separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let middle = stack([scroll, separator, editor], horizontal: true, spacing: 20)
        middle.alignment = .top
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)

        learningToggle.title = local("Use and remember word and association choices")
        learningToggle.setButtonType(.switch)
        learningToggle.target = self
        learningToggle.action = #selector(toggleLearning)
        let clear = button("Clear Learning", #selector(clearLearning))
        let memoryRow = stack([learningToggle, NSView(), clear], horizontal: true)
        learningStatus.font = .systemFont(ofSize: 12)
        learningStatus.textColor = .secondaryLabelColor
        wordCount.font = .systemFont(ofSize: 12)
        wordCount.textColor = .secondaryLabelColor
        let divider = NSBox()
        divider.boxType = .separator
        let root = stack([top, searchRow, middle, wordCount, divider, memoryRow, learningStatus], spacing: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            top.widthAnchor.constraint(equalTo: root.widthAnchor),
            searchRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            middle.widthAnchor.constraint(equalTo: root.widthAnchor),
            divider.widthAnchor.constraint(equalTo: root.widthAnchor),
            memoryRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.heightAnchor.constraint(equalTo: middle.heightAnchor),
            middle.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            separator.heightAnchor.constraint(equalTo: middle.heightAnchor),
            message.widthAnchor.constraint(equalTo: editor.widthAnchor),
        ])
    }

    public func showAndActivate() {
        reloadFromDisk()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if entries.isEmpty { window?.makeFirstResponder(phraseField) }
    }

    public func reloadFromDisk() {
        do {
            entries = try store.entries()
            applyFilter()
            refreshLearning()
            updateButtons()
        } catch { showError(error) }
    }

    private func applyFilter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visible = entries.filter { query.isEmpty || displayPhrase($0.phrase).localizedCaseInsensitiveContains(query) || $0.reading.localizedCaseInsensitiveContains(query.replacingOccurrences(of: " ", with: "-")) }
        reloading = true
        table.reloadData()
        if let editing, let row = visible.firstIndex(where: { $0.id == editing.id }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        reloading = false
        wordCount.stringValue = String(format: local("%ld words in your personal lexicon"), entries.count)
    }

    private func validatedDraft() throws -> UserPhrase {
        let result = try UserPhrase(phrase: canonicalize(phraseField.stringValue), reading: readingField.stringValue).validated()
        guard readingSupported(result.reading) else { throw UserDataError.invalidReading }
        return result
    }
    private var draft: UserPhrase? { try? validatedDraft() }
    private var isDirty: Bool {
        if phraseField.stringValue.isEmpty && readingField.stringValue.isEmpty { return false }
        return draft != editing
    }
    private func updateButtons() {
        saveButton.isEnabled = draft != nil && (editing == nil || isDirty)
        deleteButton.isEnabled = editing != nil && !isDirty
        saveButton.title = local(editing == nil ? "Add Word" : "Save Changes")
    }
    private func showError(_ error: Error) {
        message.stringValue = error.localizedDescription
        message.textColor = .systemRed
    }
    private func confirmDiscardChanges() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = local("Keep editing this word?")
        alert.informativeText = local("This word has unsaved changes.")
        alert.addButton(withTitle: local("Keep Editing"))
        alert.addButton(withTitle: local("Discard Changes"))
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        phraseField.stringValue = editing.map { displayPhrase($0.phrase) } ?? ""
        readingField.stringValue = editing?.reading.replacingOccurrences(of: "-", with: " ") ?? ""
        message.stringValue = ""
        updateButtons()
        return true
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visible.indices.contains(row), let column = tableColumn else { return nil }
        let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = column.identifier
        if cell.textField == nil {
            let text = NSTextField(labelWithString: "")
            text.font = .systemFont(ofSize: 13)
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let entry = visible[row]
        cell.textField?.stringValue = column.identifier.rawValue == "phrase" ? displayPhrase(entry.phrase) : entry.reading.replacingOccurrences(of: "-", with: " ")
        cell.toolTip = cell.textField?.stringValue
        return cell
    }
    public func selectionShouldChange(in tableView: NSTableView) -> Bool { reloading || confirmDiscardChanges() }
    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, visible.indices.contains(table.selectedRow) else { return }
        editing = visible[table.selectedRow]
        phraseField.stringValue = displayPhrase(editing!.phrase)
        readingField.stringValue = editing!.reading.replacingOccurrences(of: "-", with: " ")
        message.stringValue = ""
        updateButtons()
    }
    public func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSSearchField === search {
            applyFilter()
        } else if !phraseField.stringValue.isEmpty && !readingField.stringValue.isEmpty {
            do { _ = try validatedDraft(); message.stringValue = "" }
            catch { showError(error) }
        }
        updateButtons()
    }
    public func windowShouldClose(_ sender: NSWindow) -> Bool { confirmDiscardChanges() }

    @objc private func newWord() {
        guard confirmDiscardChanges() else { return }
        reloading = true
        table.deselectAll(nil)
        reloading = false
        editing = nil
        phraseField.stringValue = ""
        readingField.stringValue = ""
        message.stringValue = ""
        updateButtons()
        window?.makeFirstResponder(phraseField)
    }
    @objc private func fillReading() {
        guard let reading = suggestReading(canonicalize(phraseField.stringValue)), !reading.isEmpty else {
            message.stringValue = local("No reading was found. Enter the Bopomofo manually.")
            message.textColor = .systemRed
            return
        }
        readingField.stringValue = reading.replacingOccurrences(of: "-", with: " ")
        do { _ = try validatedDraft(); message.stringValue = "" }
        catch { showError(error) }
        updateButtons()
    }
    @objc private func saveWord() {
        guard let draft else { return }
        do {
            try store.upsert(draft, replacing: editing)
            editing = draft
            phraseField.stringValue = displayPhrase(draft.phrase)
            readingField.stringValue = draft.reading.replacingOccurrences(of: "-", with: " ")
            didSave()
            reloadFromDisk()
            message.textColor = .secondaryLabelColor
            message.stringValue = local("Saved. The word is available immediately.")
        } catch { showError(error) }
    }
    @objc private func deleteWord() {
        guard let editing, !isDirty else { return }
        let alert = NSAlert()
        alert.messageText = String(format: local("Delete %@ from your personal lexicon?"), displayPhrase(editing.phrase))
        alert.addButton(withTitle: local("Cancel"))
        alert.addButton(withTitle: local("Delete Word"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            try store.remove(editing)
            self.editing = nil
            phraseField.stringValue = ""
            readingField.stringValue = ""
            didSave()
            reloadFromDisk()
            message.stringValue = local("Word deleted.")
        } catch { showError(error) }
    }
    @objc private func importPhrases() {
        guard confirmDiscardChanges(), let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do {
                let count = try self.store.importJSON(Data(contentsOf: url))
                self.didSave()
                self.reloadFromDisk()
                self.message.textColor = .secondaryLabelColor
                self.message.stringValue = String(format: local("Imported %ld new words."), count)
            } catch { self.showError(error) }
        }
    }
    @objc private func exportPhrases() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Jianfan-UserPhrases.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do {
                try self.store.exportJSON().write(to: url, options: .atomic)
                self.message.textColor = .secondaryLabelColor
                self.message.stringValue = local("Phrase backup saved.")
            } catch { self.showError(error) }
        }
    }
    @objc private func toggleLearning() {
        learning.setEnabled(learningToggle.state == .on)
        refreshLearning()
    }
    @objc private func clearLearning() {
        let alert = NSAlert()
        alert.messageText = local("Clear word and association memories?")
        alert.informativeText = local("Words added to your personal lexicon will be kept.")
        alert.addButton(withTitle: local("Cancel"))
        alert.addButton(withTitle: local("Clear Learning"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        learning.clear()
        refreshLearning()
    }
    private func refreshLearning() {
        learningToggle.state = learning.isEnabled() ? .on : .off
        if let error = learning.lastError() {
            learningStatus.stringValue = local(error)
            learningStatus.textColor = .systemRed
        } else {
            learningStatus.stringValue = String(format: local("%ld remembered choices. Everything stays on this device."), learning.recordCount())
            learningStatus.textColor = .secondaryLabelColor
        }
    }
}
#endif
