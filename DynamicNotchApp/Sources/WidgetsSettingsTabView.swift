// Settings ▸ Nook ▸ Widgets: the widgets in the Nook in notch order (drag to reorder, remove), the
// widgets that can be added, and the selected widget's settings pane (a SettingsForm that fills the
// detail column and scrolls by itself).
import SwiftUI

struct WidgetsSettingsTabView: View {
    @StoredSetting(.nookSettings) private var nookSettings
    @State private var navigation = NookSettingsNavigation.shared

    private var selection: NookWidget {
        navigation.widget ?? nookSettings.widgets.first ?? NookWidget.allCases[0]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            NookWidgetPagesSettingsList() // F9: pages (was `widgetList`)
                .frame(width: 230)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: selection.icon)
                        .font(.title3)
                        .frame(width: 24)
                    Text(LocalizedStringKey(selection.name))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if nookSettings.widgets.contains(selection) {
                        Button("Remove from Nook") { remove(selection) }
                    } else {
                        Button("Add to Nook") { add(selection) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                settings(for: selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Add / remove (through the pages, like the list: NookSettings.addWidget / removeWidget)

    private func add(_ widget: NookWidget) {
        guard !nookSettings.widgets.contains(widget) else { return }
        nookSettings.addWidget(widget)
        navigation.widget = widget
    }

    private func remove(_ widget: NookWidget) {
        nookSettings.removeWidget(widget)
    }

    // MARK: - Per-widget settings

    @ViewBuilder
    private func settings(for widget: NookWidget) -> some View {
        switch widget {
        case .shortcuts:
            ShortcutsWidgetSettingsView()
        case .media:
            NoOptionsSettingsView()
        case .quickApps:
            QuickAppsWidgetSettingsView()
        case .mirror:
            MirrorWidgetSettingsView()
        case .calendar:
            CalendarWidgetSettingsView()
        case .notes:
            NotesWidgetSettingsView()
        case .timer:
            TimerWidgetSettingsView()
        #if canImport(FanControlKit) // fan-control-integration.md (c)
        case .fanControl:
            FanControlWidgetSettingsView()
        #endif
        case .clipboard:
            ClipboardWidgetSettingsView()
        case .menuBarItems:
            MenuBarItemsWidgetSettingsView()
        case .reminders:
            RemindersWidgetSettingsView()
        case .storage:
            StorageWidgetSettingsView()
        case .systemStats:
            SystemStatsWidgetSettingsView()
        case .capture:
            CaptureWidgetSettingsView()
        case .nextUp:
            NextUpWidgetSettingsView()
        #if canImport(FanControlKit) // fan-control-integration.md (c)
        case .temperature:
            FanControlTemperatureWidgetSettingsView()
        #endif
        case .batteries:
            BatteriesWidgetSettingsView()
        case .calculator:
            CalculatorWidgetSettingsView()
        case .pomodoro:
            PomodoroWidgetSettingsView()
        case .bluetooth:
            BluetoothWidgetSettingsView()
        case .weather:
            WeatherWidgetSettingsView()
        case .network:
            NetworkWidgetSettingsView()
        case .audioDevices:
            AudioDevicesWidgetSettingsView()
        case .worldClocks:
            WorldClockWidgetSettingsView()
        case .keepAwake:
            KeepAwakeWidgetSettingsView()
        case .colorPicker:
            ColorPickerWidgetSettingsView()
        case .downloads:
            DownloadsWidgetSettingsView()
        case .usage:
            UsageWidgetSettingsView()
        case .displays:
            DisplaysWidgetSettingsView()
        }
    }
}
