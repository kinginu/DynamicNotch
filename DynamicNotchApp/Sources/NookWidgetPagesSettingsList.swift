// F9 (widget pages): the widget list of Settings ▸ Nook ▸ Widgets, with pages.
//
// Replaces WidgetsSettingsTabView's former `widgetList` (same rows, selection and add / remove).
// One page: exactly the previous list (drag to reorder). Several pages: one List section whose
// rows are a "Page n" header per page followed by its widgets, so `.onMove` can carry a widget
// across pages (NookPagesModel.moveRows); headers are not draggable. "Add Page" appends an empty
// page; a header's minus button removes its page (its widgets join the previous page).
import SwiftUI

struct NookWidgetPagesSettingsList: View {
    @StoredSetting(.nookSettings) private var nookSettings
    @State private var navigation = NookSettingsNavigation.shared

    private var selection: NookWidget {
        navigation.widget ?? nookSettings.widgets.first ?? NookWidget.allCases[0]
    }

    private var availableWidgets: [NookWidget] {
        NookWidget.allCases.filter { !nookSettings.widgets.contains($0) }
    }

    var body: some View {
        let pages = nookSettings.pages
        List(selection: Binding<NookWidget?>(
            get: { selection },
            set: { navigation.widget = $0 }
        )) {
            Section {
                if pages.count == 1 && nookSettings.widgets.isEmpty {
                    Text("No widgets in the Nook")
                        .foregroundStyle(.secondary)
                }
                ForEach(NookPagesModel.rows(pages), id: \.self) { row in
                    switch row {
                    case .page(let p):
                        pageHeader(p, of: pages)
                            .moveDisabled(true)
                    case .item(let widget):
                        widgetRow(widget, active: true)
                            .tag(widget)
                    }
                }
                .onMove { from, to in
                    nookSettings.pages = NookPagesModel.moveRows(in: nookSettings.pages, fromOffsets: from, toOffset: to)
                }
                Button {
                    nookSettings.pages = NookPagesModel.addPage(nookSettings.pages)
                } label: {
                    Label("Add Page", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.borderless)
                .help("Add a page of widgets to the Nook (swipe or use the page dots to switch pages)")
                Text("Hold ⌥ and drag a widget to move it, or press and hold its header")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(pages.count > 1 ? "In the Nook (drag between pages)" : "In the Nook (drag to reorder)")
            }
            if !availableWidgets.isEmpty {
                Section {
                    ForEach(availableWidgets) { widget in
                        widgetRow(widget, active: false)
                            .tag(widget)
                    }
                } header: {
                    Text("Available")
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func pageHeader(_ p: Int, of pages: [[NookWidget]]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.3x1")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text("Page \(p + 1)")
                .font(.subheadline.weight(.semibold))
            if pages[p].isEmpty {
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                nookSettings.pages = NookPagesModel.removePage(p, from: nookSettings.pages)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(pages[p].isEmpty ? "Remove Page" : "Remove Page (its widgets move to the previous page)")
        }
        .padding(.top, p == 0 ? 0 : 6)
        .contentShape(Rectangle())
    }

    private func widgetRow(_ widget: NookWidget, active: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: widget.icon)
                .frame(width: 18)
                .foregroundStyle(active ? Color.accentColor : .secondary)
            Text(LocalizedStringKey(widget.name))
                .foregroundStyle(active ? .primary : .secondary)
            Spacer()
            Button {
                active ? remove(widget) : add(widget)
            } label: {
                Image(systemName: active ? "minus.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(active ? Color.red.opacity(0.85) : Color.green)
            }
            .buttonStyle(.plain)
            .help(active ? String(localized: "Remove from Nook") : String(localized: "Add to Nook"))
        }
        .contentShape(Rectangle())
    }

    /// Added widgets go to the last page; both go through `NookSettings.pages` (shared with the
    /// detail pane's Add / Remove buttons in WidgetsSettingsTabView).
    private func add(_ widget: NookWidget) {
        guard !nookSettings.widgets.contains(widget) else { return }
        nookSettings.addWidget(widget)
        navigation.widget = widget
    }

    private func remove(_ widget: NookWidget) {
        nookSettings.removeWidget(widget)
    }
}
