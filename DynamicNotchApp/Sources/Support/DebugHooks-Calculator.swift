// DEBUG-only commands of the Calculator widget (2026-10-20), registered with
// DebugCommandRegistry by DebugHooks.install (`CalculatorDebug.install()`, also still called when
// the widget appears, only re-registers).
//   calceval:<input>     log the evaluation of <input> ("[Calculator] …")
//   calcpreview:<dir>    write <dir>/calculator-<case>-<dark|light>.png: the widget offscreen at
//                        250 × 202 pt for sample inputs (arithmetic, units, currency, base, time
//                        zone, error, empty) with a sample history (preview only: the history
//                        file is not written), and settings-<dark|light>.png (520 pt).
#if DEBUG
import SwiftUI
import AppKit

@MainActor
enum CalculatorDebug {
    static func install() {
        DebugCommandRegistry.register("calceval", usage: "calceval:<input>", "log the evaluation of <input>") { arg in
            CalculatorRatesStore.shared.refreshIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                var context = CalculatorContext()
                context.rates = CalculatorRatesStore.shared.table
                NSLog("[Calculator] %@ → %@", arg, "\(CalculatorEngine.evaluate(arg, context: context))")
            }
        }
        DebugCommandRegistry.register("calcpreview", usage: "calcpreview:<dir>", "Calculator widget for sample inputs + settings (~3 s, rates)") { arg in
            CalculatorRatesStore.shared.refreshIfNeeded()
            // give the rate request a moment (offline: the cache or the error state is shown)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                WidgetSnapshotter.session(arg, tag: "[Calculator]") { preview(to: $0) }
            }
        }
    }

    static let sampleHistory: [CalculatorHistoryItem] = [
        CalculatorHistoryItem(expression: "12 km in mi", result: "7.456454 mi", number: 7.456454),
        CalculatorHistoryItem(expression: "72 F to C", result: "22.222222°C", number: 22.222222),
        CalculatorHistoryItem(expression: "3 h 20 min in s", result: "12,000 s", number: 12_000),
        CalculatorHistoryItem(expression: "255 in hex", result: "0xFF", number: 255),
        CalculatorHistoryItem(expression: "(1 + 2) * 3^2", result: "27", number: 27),
        CalculatorHistoryItem(expression: "15% of 80", result: "12", number: 12),
    ]

    private static func preview(to dir: URL) {
        let store = CalculatorHistoryStore.shared
        let savedItems = store.items
        let savedPersists = store.persists
        store.setPreviewItems(sampleHistory)
        defer {
            store.setPreviewItems(savedItems)
            store.persists = savedPersists
        }
        let cases: [(String, String)] = [
            ("arith", "(1 + 2) * 3^2 + sqrt(16)"),
            ("units", "3 h 20 min in s"),
            ("currency", "100 usd in jpy"),
            ("base", "0xff + 1"),
            ("time", "15:00 JST in PST"),
            ("error", "1 km + 1 kg"),
            ("empty", ""),
        ]
        let width = NookWidgetLayout.width(of: .calculator)
        for (name, input) in cases {
            let ctx = CalculatorContext(rates: CalculatorRatesStore.shared.table)
            NSLog("[Calculator] %@ → %@", input, "\(CalculatorEngine.evaluate(input, context: ctx))")
            WidgetSnapshotter.widget("calculator-\(name)", in: dir, width: width) { CalculatorWidgetView(previewInput: input) }
        }
        // no history (first use)
        store.setPreviewItems([])
        WidgetSnapshotter.widget("calculator-first", in: dir, width: width) { CalculatorWidgetView(previewInput: "") }
        store.setPreviewItems(sampleHistory)
        WidgetSnapshotter.settings("settings", in: dir, size: CGSize(width: 520, height: 600)) { CalculatorWidgetSettingsView() }
    }
}
#endif
