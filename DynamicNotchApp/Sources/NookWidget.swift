import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import SwiftUI

// MARK: - NookWidget

enum NookWidget: MetaInfo, CaseIterable, Decodable, Encodable, Equatable, Hashable, Identifiable, RawRepresentable {

    case calendar      /* tag 0, icon "calendar" */
    case media         /* tag 1, icon "music.note" */
    case shortcuts     /* tag 2, icon "sparkles" */
    case mirror        /* tag 3, icon "webcam.filled"; shown as "Camera" (raw value / settings key stay "mirror") */
    case notes         /* tag 4, icon "note.text" */
    case quickApps     /* tag 5, localization-based icon */
    // tag 6 (`todos`, the SwiftData to-do list) was removed 2026-10-20 (UI requirement (6): replaced
    // by the Apple Reminders widget). Stored "todos" values decode as `.reminders` (init(rawValue:)).
    case timer         /* tag 7, icon "timer" */
    #if canImport(FanControlKit) // fan-control-integration.md (a): tag 8, appended to keep stored values
    case fanControl
    #endif
    case clipboard     /* tag 9 (2026-10-20): clipboard history (ClipboardWidgetView) */
    case menuBarItems  /* tag 26 (2026-10-20): hidden menu bar items (MenuBarItemsWidgetView) */
    case reminders     /* tag 10 (2026-10-20): Apple Reminders via EventKit (RemindersWidgetView) */
    case storage       /* tag 21 (2026-10-20): mounted volumes, used/free (StorageWidgetView) */
    case systemStats   /* tag 15 (2026-10-20): CPU / GPU / memory / disk (SystemStatsWidgetView) */
    case nextUp        /* tag 25 (2026-10-20): next calendar events + countdown (NextUpWidgetView) */
    #if canImport(FanControlKit) // fan-control-integration.md (a): tag 11 (2026-10-20), CPU / GPU / SSD history
    case temperature
    #endif
    case batteries     /* tag 12 (2026-10-20): this Mac + accessories (BatteriesWidgetView) */
    case calculator    /* tag 20 (2026-10-20): evaluate-as-you-type calculator / converter (CalculatorWidgetView) */
    case bluetooth     /* tag 23 (2026-10-20): paired devices, connect / disconnect (BluetoothWidgetView) */
    case pomodoro      /* tag 22 (2026-10-20): Focus / Pomodoro timer (PomodoroWidgetView) */
    case weather       /* tag 18 (2026-10-20): Open-Meteo forecast (WeatherWidgetView) */
    case network       /* tag 14 (2026-10-20): Wi‑Fi / Ethernet / VPN, addresses, throughput (NetworkWidgetView) */
    case audioDevices  /* tag 13 (2026-10-20): output / input devices, volume (AudioDevicesWidgetView) */
    case worldClocks   /* tag 16 (2026-10-20): world clock tiles (WorldClockWidgetView) */
    case keepAwake     /* tag 17 (2026-10-20): IOKit power assertion with a countdown (KeepAwakeWidgetView) */
    case colorPicker   /* tag 19 (2026-10-20): screen colour sampler + history (ColorPickerWidgetView) */
    case capture       /* tag 24 (2026-10-20): screenshots / screen recording (CaptureWidgetView) */
    case downloads     /* tag 27 (2026-10-20): newest items of ~/Downloads + progress (DownloadsWidgetView) */
    case usage         /* tag 28 (2026-10-20): self-collected app usage, Screen Time-like (UsageWidgetView) */
    case displays      /* tag 29 (2026-10-20): connected displays, brightness / DDC/CI (DisplaysWidgetView) */

    // MARK: - MetaInfo conformance

    var icon: String {
        switch self {
        case .calendar:   return "calendar"
        case .media:      return "music.note"
        case .shortcuts:  return "sparkles"
        case .mirror:     return "web.camera"          // "webcam.filled" is not an SF Symbol (rendered blank); outline like the other widget icons
        case .notes:      return "note.text"
        case .quickApps:  return "square.grid.3x3"     /* localized from "square.grid.3x3.fill" pattern */
        case .timer:      return "timer"
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case .fanControl: return "fan"
        #endif
        case .clipboard:  return "doc.on.clipboard"
        case .menuBarItems: return "menubar.rectangle"
        case .reminders:  return "checklist"
        case .storage:    return "internaldrive"
        case .systemStats: return "gauge.with.dots.needle.33percent"
        case .capture:    return "camera.viewfinder"
        case .nextUp:     return "clock.badge"
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case .temperature: return "thermometer.medium"
        #endif
        case .batteries:  return "battery.100percent"
        case .calculator: return "function"
        case .bluetooth:  return "dot.radiowaves.left.and.right"  // no "bluetooth" SF Symbol exists
        case .pomodoro:   return "brain.head.profile"
        case .weather:    return "cloud.sun"
        case .network:    return "wifi"
        case .audioDevices: return "speaker.wave.2"
        case .worldClocks: return "globe"
        case .keepAwake:  return "cup.and.saucer"
        case .colorPicker: return "eyedropper"
        case .downloads:  return "arrow.down.circle"
        case .usage:      return "hourglass"
        case .displays:   return "display"
        }
    }

    var name: String {
        switch self {
        case .calendar:   return "Calendar"
        case .media:      return "Media Player"
        case .shortcuts:  return "Shortcuts"
        case .mirror:     return "Camera"         // was "Mirror"; display name only
        case .notes:      return "Notes"
        case .quickApps:  return "Quick Apps"
        case .timer:      return "Timer"
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case .fanControl: return "Fan Control"    // Localizable.strings key
        #endif
        case .clipboard:  return "Clipboard"      // Localizable.strings key
        case .menuBarItems: return "Menu Bar"     // Localizable.strings key
        case .reminders:  return "Reminders"      // Localizable.strings key
        case .storage:    return "Storage"        // Localizable.strings key
        case .systemStats: return "System"        // Localizable.strings key
        case .capture:    return "Capture"        // Localizable.strings key
        case .nextUp:     return "Next Up"        // Localizable.strings key
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case .temperature: return "Temperature"   // Localizable.strings key (FanControl)
        #endif
        case .batteries:  return "Batteries"      // Localizable.strings key
        case .calculator: return "Calculator"     // Localizable.strings key
        case .bluetooth:  return "Bluetooth"      // Localizable.strings key
        case .pomodoro:   return "Focus"          // Localizable.strings key
        case .weather:    return "Weather"        // Localizable.strings key
        case .network:    return "Network"        // Localizable.strings key
        case .audioDevices: return "Audio"        // Localizable.strings key
        case .worldClocks: return "World Clock"   // Localizable.strings key
        case .keepAwake:  return "Keep Awake"     // Localizable.strings key
        case .colorPicker: return "Color Picker"  // Localizable.strings key
        case .downloads:  return "Downloads"      // Localizable.strings key
        case .usage:      return "Usage"          // Localizable.strings key
        case .displays:   return "Displays"       // Localizable.strings key
        }
    }

    var gridSizeType: NookGridSizeType {
        switch self {
        case .calendar:   return .small
        case .media:      return .doubleWide  // 2-wide x 1-tall
        case .shortcuts:  return .small
        case .mirror:     return .medium
        case .notes:      return .small
        case .quickApps:  return .medium
        case .timer:      return .small
        #if canImport(FanControlKit) // fan-control-integration.md (a): 2x1 = .medium (100 pt) / 2w×1h = .doubleWide (250 pt)
        case .fanControl:
            return SettingsStore[.fanControlWidgetSettings].gridSize == .doubleWide ? .doubleWide : .medium
        #endif
        case .clipboard:  return .small
        case .menuBarItems: return .small      // width: NookWidgetLayout.cells (5 = 250 pt)
        case .reminders:  return .small
        case .storage:    return .small          // width: StorageWidgetLayout (4 cells)
        case .systemStats: return .doubleWide     // 5 cells (250 pt)
        case .capture:    return .small
        case .nextUp:     return .small         // width: NookWidgetLayout (5 cells)
        #if canImport(FanControlKit) // fan-control-integration.md (a): 5 cells (250 pt)
        case .temperature: return .doubleWide
        #endif
        case .batteries:  return .small        // width: BatteriesWidgetLayout (4 or 8 cells)
        case .calculator: return .small        // width: NookWidgetLayout.cells (5 = 250 pt)
        case .bluetooth:  return .small
        case .pomodoro:   return .small        // width: NookWidgetLayout (4 cells)
        case .weather:    return .small          // width: NookWidgetLayout.cells (4 cells)
        case .network:    return .small        // width: 4 cells (NookWidgetLayout)
        case .audioDevices: return .small      // width: AudioDevicesWidgetLayout (4 or 8 cells)
        case .worldClocks: return .small       // width: WorldClockWidgetLayout (one tile per clock)
        case .keepAwake:  return .small        // width: 4 cells (NookWidgetLayout)
        case .colorPicker: return .small       // width: NookWidgetLayout.cells (4 = 200 pt)
        case .downloads:  return .small        // width: DownloadsWidgetLayout.cells (5 = 250 pt)
        case .usage:      return .small        // width: NookWidgetLayout.cells (5 = 250 pt)
        case .displays:   return .small        // width: DisplaysWidgetLayout.cells (5 = 250 pt)
        }
    }

    // Dispatch pattern (tag-based switch to Defaults key fetch):
    //   tag 0: CalendarWidgetSettings via CalendarWidgetSettingsKey
    //   tag 1: MediaWidgetSettings via MediaWidgetSettingsKey
    //   tag 2: ShortcutsWidgetSettings via ShortcutsWidgetSettingsKey
    //   tag 3: MirrorWidgetSettings via MirrorWidgetSettingsKey
    //   tag 4: NotesWidgetSettings via NotesWidgetSettingsKey
    //   tag 5: QuickAppsWidgetSettings via QuickAppsWidgetSettingsKey
    //   tag 6: TodoListWidgetSettings via TodoListWidgetSettingsKey
    //   tag 7: TimerWidgetSettings via TimerWidgetSettingsKey
    // the *Key types are EnvironmentKeys; read the stored-setting keys of the same name
    var prefs: WidgetPrefs {
        switch self {
        case .calendar:   return SettingsStore[.calendarWidgetSettings]   /* key → settings store */
        case .media:      return SettingsStore[.mediaWidgetSettings]      /* */
        case .shortcuts:  return SettingsStore[.shortcutsWidgetSettings] /* */
        case .mirror:     return SettingsStore[.mirrorWidgetSettings]    /* */
        case .notes:      return SettingsStore[.notesWidgetSettings]     /* */
        case .quickApps:  return SettingsStore[.quickAppsWidgetSettings] /* */
        case .timer:      return SettingsStore[.timerWidgetSettings]     /* */
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case .fanControl: return SettingsStore[.fanControlWidgetSettings]
        #endif
        case .clipboard:  return SettingsStore[.clipboardWidgetSettings]
        case .menuBarItems: return SettingsStore[.menuBarItemsWidgetSettings]
        case .reminders:  return SettingsStore[.remindersWidgetSettings]
        case .storage:    return SettingsStore[.storageWidgetSettings]
        case .systemStats: return SettingsStore[.systemStatsWidgetSettings]
        case .capture:    return SettingsStore[.captureWidgetSettings]
        case .nextUp:     return SettingsStore[.nextUpWidgetSettings]
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case .temperature: return SettingsStore[.fanControlTemperatureWidgetSettings]
        #endif
        case .batteries:  return SettingsStore[.batteriesWidgetSettings]
        case .calculator: return SettingsStore[.calculatorWidgetSettings]
        case .bluetooth:  return SettingsStore[.bluetoothWidgetSettings]
        case .pomodoro:   return SettingsStore[.pomodoroWidgetSettings]
        case .weather:    return SettingsStore[.weatherWidgetSettings]
        case .network:    return SettingsStore[.networkWidgetSettings]
        case .audioDevices: return SettingsStore[.audioDevicesWidgetSettings]
        case .worldClocks: return SettingsStore[.worldClocksWidgetSettings]
        case .keepAwake:  return SettingsStore[.keepAwakeWidgetSettings]
        case .colorPicker: return SettingsStore[.colorPickerWidgetSettings]
        case .downloads:  return SettingsStore[.downloadsWidgetSettings]
        case .usage:      return SettingsStore[.usageWidgetSettings]
        case .displays:   return SettingsStore[.displaysWidgetSettings]
        }
    }

    // MARK: - Identifiable / RawRepresentable

    // id from CaseIterable index, rawValue from case name
    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .calendar:  return "calendar"
        case .media:     return "media"
        case .shortcuts: return "shortcuts"
        case .mirror:    return "mirror"
        case .notes:     return "notes"
        case .quickApps: return "quickApps"
        case .timer:     return "timer"
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case .fanControl: return "fanControl"
        #endif
        case .clipboard: return "clipboard"
        case .menuBarItems: return "menuBarItems"
        case .reminders: return "reminders"
        case .storage:   return "storage"
        case .systemStats: return "systemStats"
        case .capture:   return "capture"
        case .nextUp: return "nextUp"
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case .temperature: return "temperature"
        #endif
        case .batteries: return "batteries"
        case .calculator: return "calculator"
        case .bluetooth: return "bluetooth"
        case .pomodoro: return "pomodoro"
        case .weather:   return "weather"
        case .network:   return "network"
        case .audioDevices: return "audioDevices"
        case .worldClocks: return "worldClocks"
        case .keepAwake: return "keepAwake"
        case .colorPicker: return "colorPicker"
        case .downloads: return "downloads"
        case .usage:     return "usage"
        case .displays: return "displays"
        }
    }

    // Standard RawRepresentable initializer
    init?(rawValue: String) {
        switch rawValue {
        case "calendar":  self = .calendar
        case "media":     self = .media
        case "shortcuts": self = .shortcuts
        case "mirror":    self = .mirror
        case "notes":     self = .notes
        case "quickApps": self = .quickApps
        case "timer":     self = .timer
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case "fanControl": self = .fanControl
        #endif
        case "clipboard": self = .clipboard
        case "menuBarItems": self = .menuBarItems
        case "reminders": self = .reminders
        case "storage":   self = .storage
        case "systemStats": self = .systemStats
        case "capture":   self = .capture
        case "nextUp": self = .nextUp
        #if canImport(FanControlKit) // fan-control-integration.md (a)
        case "temperature": self = .temperature
        #endif
        case "batteries": self = .batteries
        case "calculator": self = .calculator
        case "bluetooth": self = .bluetooth
        case "pomodoro":  self = .pomodoro
        case "weather":   self = .weather
        case "network":   self = .network
        case "audioDevices": self = .audioDevices
        case "worldClocks": self = .worldClocks
        case "keepAwake": self = .keepAwake
        case "colorPicker": self = .colorPicker
        case "downloads": self = .downloads
        case "usage":     self = .usage
        case "displays": self = .displays
        // the removed SwiftData to-do widget: its slot in the Nook becomes the Reminders widget
        case "todos":     self = .reminders
        default:          return nil
        }
    }

    // MARK: - CustomStringConvertible

    // If gridSizeType == .small, returns "cells " + size; else prefs.description + " cells " + size
    var description: String {
        let size = gridSizeType
        if size == .small {
            return "cells \(size.description)"
        } else {
            return "\(String(describing: prefs)) cells \(size.description)"
        }
    }
}

// MARK: - NookGridSizeType

// Tags 0=small, 2=medium, 5=doubleWide (2x1 grid)
extension NookWidget {
    enum NookGridSizeType: Int, Equatable, Hashable, CaseIterable, CustomStringConvertible {
        case small      = 0 /* 1x1 cell */
        case medium     = 2 /* 1-wide grid, 2x1 */
        case doubleWide = 5 /* 2-wide x 1-tall, MediaWidget uses this */

        var description: String {
            switch self {
            case .small:      return "1x1"
            case .medium:     return "2x1"
            case .doubleWide: return "2w x 1h"
            }
        }
    }
}


#if canImport(FanControlKit) // fan-control-integration.md (a): settings type conformances
import FanControlCore
import FanControlKit

extension FanControlWidgetSettings: Preferences, WidgetPrefs {
    // `Preferences` requires a bare `init()`; the memberwise init with all-default
    // arguments does not satisfy it.
    init() { self.init(gridSize: .medium) }

    var gridSizeType: NookWidget.NookGridSizeType {
        gridSize == .doubleWide ? .doubleWide : .medium
    }
}

// Temperature widget (2026-10-20): always 5 cells (250 pt).
extension FanControlTemperatureWidgetSettings: Preferences, WidgetPrefs {
    init() { self.init(historyWindow: .fiveMinutes) }

    var gridSizeType: NookWidget.NookGridSizeType { .doubleWide }
}
#endif
