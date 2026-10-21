// The data-source attribution at the end of a settings pane ("Weather data by Open-Meteo.com"),
// with the source's terms in the footer. Open-Meteo requires the attribution (free for
// non-commercial use, data under CC BY 4.0).
import SwiftUI

struct SettingsAttributionSection: View {
    /// Text before the link ("Weather data by").
    let prefix: LocalizedStringKey
    /// Link title (the provider's name, not localized).
    let provider: String
    let url: URL
    /// The provider's terms (footer).
    let terms: LocalizedStringKey

    var body: some View {
        Section {
            HStack(spacing: 4) {
                Text(prefix)
                Link(provider, destination: url)
            }
            .font(.callout)
        } footer: {
            Text(terms).settingsFootnote()
        }
    }
}
