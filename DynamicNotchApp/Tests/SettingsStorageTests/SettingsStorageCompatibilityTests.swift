// Compatibility of SettingsStore (Sources/Support/SettingsStorage.swift) with the settings that
// sindresorhus/Defaults 8.2 wrote before the migration (2026-10-20).
//
// The fixture is a copy of the setting keys of the user's domain
// (`defaults export com.example.dynamicnotch.DynamicNotch -`, 2026-10-20, only the SettingKey
// names). Set DN_SETTINGS_PLIST to another export (binary or XML plist) to run the same checks
// against it; the live domain is never read or written (each test uses a throw-away suite).
//
// The Fan Control keys (Sources/FanControlGlue/, not compiled by this harness) are checked by
// FanControl's own tests (Tests/FanControlUITests/FanControlSettingsStorageTests.swift).
import Foundation
import Observation
import Testing
@testable import DynamicNotchApp

private func loadFixture() throws -> [String: Any] {
    let path = ProcessInfo.processInfo.environment["DN_SETTINGS_PLIST"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/settings-2026-10-20.plist").path
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    var plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #if !canImport(FanControlKit)
    // The harness compiles NookWidget without `case fanControl` (`#if canImport(FanControlKit)`), so
    // a stored "fanControl" widget would not decode here — with Defaults or SettingsStore alike.
    // Drop it from the copy; the Xcode target (which has the case) decodes the original.
    if let string = plist["nookSettings"] as? String, string.contains(#""fanControl""#) {
        plist["nookSettings"] = string.replacingOccurrences(of: #""fanControl","#, with: "")
            .replacingOccurrences(of: #","fanControl""#, with: "")
            .replacingOccurrences(of: #""fanControl""#, with: "")
        print("note: harness without FanControlKit — removed \"fanControl\" from nookSettings.widgets")
    }
    #endif
    return plist
}

/// A store on a throw-away suite pre-filled with `contents`.
private func makeStore(_ contents: [String: Any]) -> (SettingsStore, UserDefaults, String) {
    let name = "SettingsStorageTests.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    for (key, value) in contents { suite.set(value, forKey: key) }
    return (SettingsStore(defaults: suite), suite, name)
}

private func json(_ string: String) -> NSObject? {
    (try? JSONSerialization.jsonObject(with: Data(string.utf8), options: [.fragmentsAllowed])) as? NSObject
}

/// Every typed key of the app with its stored representation.
private struct KeyCheck {
    let name: String
    /// Decodes the fixture object (nil = would fall back to the default) and re-encodes it.
    let roundTrip: (Any) -> (decoded: String, reencoded: Any?)?
    /// Value read through the store (description).
    let read: (SettingsStore) -> String
    /// Encoding of the key's default value.
    let encodedDefault: () -> Any?

    init<Value>(_ key: StoredKey<Value>) {
        name = key.name
        roundTrip = { object in
            guard let value = Value.fromStoredObject(object) else { return nil }
            return (String(describing: value), value.storedObject)
        }
        read = { String(describing: $0.value(key)) }
        encodedDefault = { key.defaultValue.storedObject }
    }
}

private let allKeys: [KeyCheck] = [
    KeyCheck(.generalSettings), KeyCheck(.gestureControlSettings), KeyCheck(.liquidGlassSettings),
    KeyCheck(.liquidBasicSettings), KeyCheck(.liveActivitiesSettings), KeyCheck(.batteryLiveActivitySettings),
    KeyCheck(.calendarLiveActivitySettings), KeyCheck(.mediaLiveActivitySettings), KeyCheck(.dropAreaSettings),
    KeyCheck(.traySettings), KeyCheck(.nookSettings), KeyCheck(.calendarWidgetSettings),
    KeyCheck(.mediaWidgetSettings), KeyCheck(.mirrorWidgetSettings), KeyCheck(.notesWidgetSettings),
    KeyCheck(.quickAppsWidgetSettings), KeyCheck(.shortcutsWidgetSettings), KeyCheck(.timerWidgetSettings),
    KeyCheck(.clipboardWidgetSettings), KeyCheck(.remindersWidgetSettings),
    KeyCheck(.intro), KeyCheck(.quickAppsPaths), KeyCheck(.shortcutsWidgetSelection),
    KeyCheck(.defaultMirrorDevice), KeyCheck(.mirrorCameraInputWhenAvail),
]

/// Value migrations done by the decoders on purpose (not storage differences).
private let knownValueMigrations: [String: String] = [
    // NookWidget.init(rawValue:) maps the removed to-do widget to Reminders.
    "nookSettings": #"widgets: "todos" → "reminders""#,
]

@Suite("SettingsStore compatibility with Defaults 8.2 data")
struct SettingsStorageCompatibilityTests {

    @Test("every typed key name is a SettingKey name, no duplicates")
    func keyNames() {
        let names = allKeys.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.contains(SettingKey.nookSettings))
    }

    @Test("stored user settings decode (no fallback to defaults) and re-encode to the same JSON")
    func userSettingsRoundTrip() throws {
        let fixture = try loadFixture()
        let (store, _, suiteName) = makeStore(fixture)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        var report: [String] = []
        for check in allKeys {
            guard let object = fixture[check.name] else {
                report.append("\(check.name): (not stored) → default \(check.read(store).prefix(120))")
                continue
            }
            let result = try #require(check.roundTrip(object), "\(check.name) did not decode: \(object)")
            report.append("\(check.name): \(type(of: object)) → \(result.decoded.prefix(200))")

            if let original = object as? String {
                // Codable: JSON string. Same sorted-key encoder → identical bytes unless the struct
                // has gained fields since the value was written (then the stored keys must match).
                let reencoded = try #require(result.reencoded as? String, "\(check.name) re-encoded to non-string")
                let identical = reencoded == original
                report.append("    stored    \(original)")
                if !identical { report.append("    re-encoded \(reencoded)") }
                report.append("    byte-identical: \(identical)")
                let a = try #require(json(original) as? [String: Any])
                let b = try #require(json(reencoded) as? [String: Any])
                for (field, value) in a {
                    let same = (b[field] as? NSObject) == (value as? NSObject)
                    if !same && knownValueMigrations[check.name] != nil { continue }
                    #expect(same, "\(check.name).\(field): stored \(value) re-encoded \(b[field] ?? "nil")")
                }
            } else {
                // Native property-list objects are stored as themselves.
                #expect((result.reencoded as? NSObject) == (object as? NSObject), "\(check.name)")
                report.append("    native, identical: \((result.reencoded as? NSObject) == (object as? NSObject))")
            }
        }
        print("SettingsStore compatibility report\n" + report.joined(separator: "\n"))
    }

    @Test("Codable values are written as sorted-key JSON strings, natives natively")
    func representation() throws {
        let (store, suite, suiteName) = makeStore([:])
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        var nook = NookSettings()
        nook.separatorSpacing = 24
        nook.widgets = [.timer, .calendar]
        store[.nookSettings] = nook
        #expect(suite.object(forKey: "nookSettings") as? String
                == #"{"separatorSpacing":24,"widgets":["timer","calendar"]}"#)

        store[.intro] = false
        #expect(suite.object(forKey: "intro") as? Bool == false)
        store[.quickAppsPaths] = ["/Applications/Safari.app"]
        #expect(suite.object(forKey: "quickAppsPaths") as? [String] == ["/Applications/Safari.app"])

        for check in allKeys {
            let encoded = check.encodedDefault()
            #expect(encoded is String || encoded is Bool || encoded is [Any], "\(check.name): \(type(of: encoded))")
        }
    }

    @Test("undecodable or wrongly typed objects read as the default (Defaults behaviour)")
    func fallback() {
        let (store, _, suiteName) = makeStore([
            "nookSettings": "{not json", "generalSettings": Data([1, 2]), "intro": "yes",
        ])
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        #expect(store[.nookSettings] == NookSettings())
        #expect(store[.generalSettings] == GeneralSettings())
        #expect(store[.intro] == true)
    }

    @Test("writes from outside the store reach updates() streams and Observation tracking")
    func changeNotifications() async throws {
        let (store, suite, suiteName) = makeStore([:])
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        // Observation: a tracked read is invalidated by a plain UserDefaults write.
        let changed = Mutex(false)
        withObservationTracking {
            _ = store.observedValue(.intro)
        } onChange: {
            changed.withLock { $0 = true }
        }
        suite.set(false, forKey: "intro")
        // delivered on the main thread
        for _ in 0..<50 where !changed.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(changed.withLock { $0 })

        // AsyncStream
        let stream = SettingsStore.updates(.quickAppsPaths, initial: true, store: store)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == [])
        suite.set(["/Applications/Notes.app"], forKey: "quickAppsPaths")
        #expect(await iterator.next() == ["/Applications/Notes.app"])
    }
}

/// Minimal lock box (Synchronization.Mutex needs a non-copyable capture; keep it simple).
private final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
