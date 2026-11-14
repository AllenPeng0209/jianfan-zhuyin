import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let ios = root.appendingPathComponent("platforms/ios")
let regex = try NSRegularExpression(pattern: #"L\("((?:\\.|[^"\\])*)"\)"#)
var keys = Set<String>()
for folder in ["App","Keyboard","Shared"] {
    let files = FileManager.default.enumerator(at: ios.appendingPathComponent(folder),includingPropertiesForKeys: nil)!
    for case let url as URL in files where url.pathExtension == "swift" {
        let source = try String(contentsOf: url,encoding: .utf8)
        for match in regex.matches(in: source,range: NSRange(source.startIndex...,in: source)) {
            let encoded = "\"" + (source as NSString).substring(with: match.range(at: 1)) + "\""
            keys.insert(try JSONSerialization.jsonObject(with: Data(encoded.utf8),options: .fragmentsAllowed) as! String)
        }
    }
}
let english: [String:String] = [
    "簡繁注音":"Jianfan Zhuyin", "開始使用":"Get started", "個人詞庫":"Personal dictionary", "輸入偏好":"Typing preferences", "關於":"About",
    "開啟系統設定":"Open Settings", "體驗鍵盤":"Try the keyboard", "管理詞庫":"Manage words", "預設簡體輸出":"Simplified output by default",
    "長期選字記憶":"Remember word choices", "清除鍵盤記憶":"Clear keyboard learning", "隱私與使用說明":"Privacy and help", "開源授權":"Open-source licenses",
    "搜尋詞語或注音":"Search words or Bopomofo", "匯入":"Import", "匯出":"Export", "新增詞語":"Add word", "編輯詞語":"Edit word", "儲存":"Save", "詞語":"Word",
    "注音，以 - 或空格分隔音節":"Bopomofo, with spaces or hyphens between syllables", "自動填入讀音":"Suggest reading",
    "最多 8 個注音音節，可用短讀音展開較長的詞語。多音字請確認讀音後儲存。":"Use up to eight syllables. A short reading can expand to a longer word. Check the suggested reading before saving.",
    "還沒有個人詞語，按 + 新增。":"No words yet. Tap + to add one.", "沒有符合的詞語。":"No matching words.",
    "在「設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤」加入簡繁注音，再以地球鍵切換。不需要開啟完整取用。":"Add Jianfan Zhuyin in Settings → General → Keyboard → Keyboards → Add New Keyboard, then switch with the globe key. Full Access is not required.",
    "共享詞庫無法使用。請確認正式簽署版本已安裝。":"The shared dictionary is unavailable. Install a correctly signed version to use it.",
    "新增專有名詞、修改讀音，或匯入其他平台匯出的 JSON 詞庫。":"Add names, edit readings, or import a JSON dictionary exported on another platform.",
    "選字記憶保存在鍵盤自己的本機空間。清除指令會在下次開啟鍵盤時生效；個人詞庫會保留。":"Learning stays in the keyboard's local storage. A clear request takes effect when you next open the keyboard. Your personal dictionary is kept.",
    "不傳送輸入內容、不追蹤、不需要網路。":"No typing uploads, no tracking, no network required.",
    "清除鍵盤記憶？":"Clear keyboard learning?", "下次開啟鍵盤時會清除選字與聯想排序紀錄，個人詞庫會保留。":"Word choices and association ranking will be cleared the next time the keyboard opens. Your personal dictionary is kept.",
    "取消":"Cancel", "清除":"Clear", "無法完成操作":"Unable to complete the action", "好":"OK", "用下方鍵盤試打，按確認送出文字。":"Type below, then tap Confirm to insert your text.",
    "詞庫無法載入，請重新安裝簡繁注音。":"The dictionary could not be loaded. Please reinstall Jianfan Zhuyin.",
    "下一個鍵盤":"Next keyboard", "聯想":"Related", "刪除":"Delete", "確認":"Confirm", "標準注音 · 離線":"Standard Bopomofo · Offline",
    "簡":"簡", "繁":"繁", "小寫":"Lowercase", "大寫":"Uppercase", "切換為繁體":"Switch to Traditional", "切換為簡體":"Switch to Simplified", "一聲":"First tone", "空白":"Space"
]
func quote(_ value: String) throws -> String {
    String(data: try JSONSerialization.data(withJSONObject: value,options: [.fragmentsAllowed,.withoutEscapingSlashes]),encoding: .utf8)!
}
for language in ["zh-Hant","zh-Hans","en"] {
    let directory = ios.appendingPathComponent("Shared/Resources/" + language + ".lproj")
    try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
    var rows: [String] = []
    for key in keys.sorted() {
        let value: String
        if language == "zh-Hans" { value = key.applyingTransform(StringTransform("Traditional-Simplified"),reverse: false) ?? key }
        else if language == "en" {
            if key.hasPrefix("簡繁注音完全離線") {
                value = "Jianfan Zhuyin works entirely offline. It does not collect or upload typing, and includes no ads or analytics.\n\nThe keyboard does not request Full Access. The main app manages your personal dictionary; the keyboard reads it and keeps learning in its own local storage.\n\nIncomplete input appears in the keyboard's composition bar. Use a tone key or First tone to complete a syllable, tap a candidate to change a word, and use Confirm or Space to insert text. Related shows phrase continuations.\n\niOS uses the system keyboard in password fields, some telephone fields, and apps that disable third-party keyboards.\n\nSource: https://github.com/AllenPeng0209/jianfan-zhuyin"
            } else { guard let translated = english[key] else { fatalError("Missing English translation: " + key) }; value = translated }
        } else { value = key }
        rows.append(try quote(key) + " = " + quote(value) + ";")
    }
    try (rows.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("Localizable.strings"),atomically: true,encoding: .utf8)
    let name = language == "en" ? "Jianfan Zhuyin" : (language == "zh-Hans" ? "简繁注音" : "簡繁注音")
    try ("\"CFBundleDisplayName\" = " + quote(name) + ";\n").write(to: directory.appendingPathComponent("InfoPlist.strings"),atomically: true,encoding: .utf8)
}
