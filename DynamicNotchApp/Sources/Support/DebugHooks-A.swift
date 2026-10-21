// DEBUG-only DebugHooks commands of the Nook settings / sample data (registered with
// DebugCommandRegistry by DebugHooks.install).
//   nooktab:<general|widgets|dropArea>   select a tab of Settings ▸ Nook
//   nookwidget:<NookWidget rawValue>      select a widget in Settings ▸ Nook ▸ Widgets (and show that tab)
//   nookwidgets:<a,b,c>                   set NookSettings.widgets (comma-separated raw values; empty = none)
//   samplenote:<text>                     insert a note (SwiftData)
//   sampletimer:<seconds>                 start a timer in NookTimersStore.shared
//   deletesample:<title prefix>           delete notes whose title starts with the prefix
//   NOTE: the SwiftData store (~/Library/Application Support/default.store) is shared by every
//   instance, including the user's; delete sample data after testing.
#if DEBUG
import AppKit
import SwiftUI
import SwiftData

extension DebugHooks {
    @MainActor static func registerCommandsA() {
        let r = DebugCommandRegistry.self
        r.register("nooktab", usage: "nooktab:<general|widgets|dropArea>", "select a tab of Settings ▸ Nook") { arg in
            if let tab = NookSettingsNavigation.Tab(rawValue: arg) { NookSettingsNavigation.shared.tab = tab }
        }
        r.register("nookwidget", usage: "nookwidget:<NookWidget rawValue>", "select a widget in Settings ▸ Nook ▸ Widgets") { arg in
            if let widget = NookWidget(rawValue: arg) {
                NookSettingsNavigation.shared.tab = .widgets
                NookSettingsNavigation.shared.widget = widget
            }
        }
        r.register("nookwidgets", usage: "nookwidgets:<a,b,c>", "set the Nook's widgets (raw values; empty = none)") { arg in
            SettingsStore[.nookSettings].widgets = arg.split(separator: ",").compactMap { NookWidget(rawValue: String($0)) }
        }
        r.register("samplenote", usage: "samplenote:<text>", "insert a note (SwiftData; \\n = newline)") { arg in
            #if !DN_CLT_HARNESS
            if let context = NookModelContainer.shared?.mainContext {
                let note = Note()
                note.richText = NSAttributedString(string: arg.replacingOccurrences(of: "\\n", with: "\n"))
                context.insert(note)
                try? context.save()
            }
            #endif
        }
        r.register("deletesample", usage: "deletesample:<title prefix>", "delete notes whose title starts with the prefix") { arg in
            #if !DN_CLT_HARNESS
            if let context = NookModelContainer.shared?.mainContext, !arg.isEmpty {
                for note in (try? context.fetch(FetchDescriptor<Note>())) ?? [] where note.title.hasPrefix(arg) {
                    context.delete(note)
                }
                try? context.save()
            }
            #endif
        }
        r.register("sampletimer", usage: "sampletimer:<seconds>", "start a timer in NookTimersStore") { arg in
            NookTimersStore.shared.add(label: "", totalSeconds: Int(arg) ?? 60)
        }
    }
}
#endif
