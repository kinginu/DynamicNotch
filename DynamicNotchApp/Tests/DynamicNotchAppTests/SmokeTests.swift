// Smoke test: the app module links into a test bundle and its basic tables are consistent.
//
// Both runners compile the same files with `@testable import DynamicNotchApp`:
//   Xcode:  xcodebuild test -scheme DynamicNotch -only-testing:DynamicNotchAppTests
//           (host-less bundle linked against the static library target `DynamicNotchApp`,
//           which compiles the app sources without `App/` — the app never launches)
//   CLT:    swift test   (Package.swift harness, library target `DynamicNotchApp`)
import Foundation
import Testing
@testable import DynamicNotchApp

@Suite("Smoke")
struct SmokeTests {
    @Test("Every Nook widget has a unique raw value and id")
    func widgetIdentifiersAreUnique() {
        let widgets = NookWidget.allCases
        #expect(!widgets.isEmpty)
        #expect(Set(widgets.map(\.rawValue)).count == widgets.count)
        #expect(Set(widgets.map(\.id)).count == widgets.count)
    }

    @Test("Widget raw values round-trip")
    func widgetRawValuesRoundTrip() {
        for widget in NookWidget.allCases {
            #expect(NookWidget(rawValue: widget.rawValue) == widget)
        }
    }

    @Test("The test process is not the app")
    func notHostedByTheApp() {
        // The tests must never launch DynamicNotch (it would open notch windows, read the SMC and
        // talk to the Fan Control helper next to the user's running instance).
        #expect(Bundle.main.bundleIdentifier != "com.example.dynamicnotch.DynamicNotch")
    }
}
