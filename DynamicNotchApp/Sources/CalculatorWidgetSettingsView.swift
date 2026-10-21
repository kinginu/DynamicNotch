// Settings of the Calculator widget (Settings ▸ Nook ▸ Widgets ▸ Calculator).
import SwiftUI

struct CalculatorWidgetSettingsView: View {
    @StoredSetting(.calculatorWidgetSettings) private var settings
    @State private var rates = CalculatorRatesStore.shared
    @State private var history = CalculatorHistoryStore.shared

    var body: some View {
        SettingsForm {
            Section {
                Picker("Convert from", selection: $settings.fromCurrency) {
                    ForEach(currencies, id: \.self) { Text(label(for: $0)).tag($0) }
                }
                Picker("Convert to", selection: $settings.toCurrency) {
                    ForEach(currencies, id: \.self) { Text(label(for: $0)).tag($0) }
                }
            } header: {
                Text("Default currency pair")
            } footer: {
                Text(ratesFooter)
                    .settingsFootnote()
            }

            Section {
                SettingsChoicePicker("Decimal digits", selection: $settings.decimalDigits,
                                     choices: CalculatorWidgetSettings.decimalDigitChoices) { n in
                    Text(n == 0 ? String(localized: "None") : "\(n)")
                }
                Toggle("Focus the field when the Nook opens", isOn: $settings.focusOnOpen)
            } footer: {
                Text("Type arithmetic (2^10, 15% of 80, sqrt(2)), units (12 km in mi, 72 F to C, 500 MB in GB), currencies (100 usd in jpy), bases (255 in hex, 0xff) or times (15:00 JST in PST). Return keeps the result in the history; click a result to copy it.")
                    .settingsFootnote()
            }

            Section {
                SettingsHistoryRow(
                    summary: history.items.count == 1
                        ? String(localized: "1 result in history")
                        : String(localized: "\(history.items.count) results in history"),
                    clearTitle: "Clear History",
                    isEmpty: history.items.isEmpty,
                    clear: { history.clear() })
            }
        }
    }

    private var currencies: [String] {
        var codes = Set(CalculatorEngine.knownCurrencies)
        if let t = rates.table { codes.formUnion(t.codes) }
        codes.insert(settings.fromCurrency)
        codes.insert(settings.toCurrency)
        return codes.sorted()
    }

    private func label(for code: String) -> String {
        if let name = Locale.current.localizedString(forCurrencyCode: code) { return "\(code) — \(name)" }
        return code
    }

    private var ratesFooter: String {
        let source = String(localized: "A bare amount such as “100 usd” converts with this pair. Rates: European Central Bank via frankfurter.app, refreshed hourly while you use currencies.")
        guard let t = rates.table else { return source }
        return source + " " + String(localized: "Current rates: \(t.date).")
    }
}
