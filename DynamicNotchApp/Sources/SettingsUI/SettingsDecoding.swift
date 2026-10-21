// Tolerant decoding of the settings structs (every `*WidgetSettings`).
//
// The pattern every settings struct follows:
//
//     struct FooWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
//         /// What the field does.
//         var showBar: Bool = true                     // the default lives here, once
//
//         static let `default` = FooWidgetSettings()
//         init() {}
//
//         // Tolerant decoding: a missing or undecodable field keeps its default; the rest of
//         // the stored value is still used (a synthesized init(from:) would drop all of it).
//         init(from decoder: Decoder) throws {
//             self.init()
//             let c = try decoder.container(keyedBy: CodingKeys.self)
//             c.decodeSetting(.showBar, into: &showBar)
//         }
//
//         private enum CodingKeys: String, CodingKey { case showBar }
//     }
//
//     extension SettingKey {                            // the UserDefaults key name (never rename)
//         static let fooWidgetSettings = "fooWidgetSettings"
//     }
//
//     extension StoredKeys {                            // the typed key, next to the struct
//         static let fooWidgetSettings = Key<FooWidgetSettings>(SettingKey.fooWidgetSettings, default: .default)
//     }
//
// Encoding stays synthesized (sorted-key JSON, SettingsStorage.swift), so the stored format does
// not change. A struct whose memberwise initializer is used keeps it by declaring `init(from:)` in
// an extension.
import Foundation

extension KeyedDecodingContainer {
    /// Replaces `value` with the stored value for `key` when there is one that decodes; otherwise
    /// (missing, `null`, wrong type, unknown enum case) leaves `value` — the default — untouched.
    func decodeSetting<T: Decodable>(_ key: Key, into value: inout T) {
        if let decoded = try? decodeIfPresent(T.self, forKey: key) {
            value = decoded
        }
    }
}
