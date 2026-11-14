import Carbon
import Foundation

let prefix = "com.local.inputmethod.JianfanZhuyin"
func property(_ source: TISInputSource, _ key: CFString) -> Any? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
}
let sources = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
var rows: [[String: Any]] = []
for source in sources {
    guard let identifier = property(source, kTISPropertyInputSourceID) as? String,
          identifier.hasPrefix(prefix) else { continue }
    var row: [String: Any] = [
        "id": identifier,
        "name": property(source, kTISPropertyLocalizedName) as? String ?? "",
        "bundle": property(source, kTISPropertyBundleID) as? String ?? "",
        "mode": property(source, kTISPropertyInputModeID) as? String ?? "",
        "enabled": property(source, kTISPropertyInputSourceIsEnabled) as? Bool ?? false,
        "enableCapable": property(source, kTISPropertyInputSourceIsEnableCapable) as? Bool ?? false,
        "selectCapable": property(source, kTISPropertyInputSourceIsSelectCapable) as? Bool ?? false,
        "selected": property(source, kTISPropertyInputSourceIsSelected) as? Bool ?? false,
    ]
    if CommandLine.arguments.contains("--enable") {
        row["enableStatus"] = TISEnableInputSource(source)
    }
    rows.append(row)
}
let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
if CommandLine.arguments.contains("--check") {
    let parentEnabled = rows.contains { ($0["id"] as? String == prefix) && ($0["enabled"] as? Bool == true) }
    let usable = parentEnabled && rows.contains { ($0["enabled"] as? Bool == true) && ($0["selectCapable"] as? Bool == true) }
    exit(usable ? 0 : 78)
}
