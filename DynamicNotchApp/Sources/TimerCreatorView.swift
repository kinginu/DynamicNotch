import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// TimerCreatorView: hours / minutes / seconds wheels in an HStack with
//   1 × 24 pt separators, a hover-following liquid-glass focus pill that deforms elastically
//   (updateMouseFollow / deform / endMouseFollow, pow(distance / colW, 0.32)), haptics on column
//   change (TimerHaptics), a close button at the top leading corner and twelve preset buttons
//   (12h … 10m, applyPreset: spring(response 0.35, damping 0.78)). The "create" path and the
//   NumberWheel data source were not recoverable, and its 120 pt wheel stack + 3 preset rows did
//   not fit the ≈200 pt tall Nook row.
//
// restyle (2026-10-20, Apple-native) — the compact creator used
//   by the Timer widget:
//   - h : m : s wheel columns (TimerWheelColumn): previous / current / next value, the current one
//     on a Liquid Glass pill (macOS 26; material before) in rounded monospaced digits. Change a
//     column by scrolling over it, dragging it vertically, clicking the neighbour values, or with
//     VoiceOver's adjustable action; values wrap like a wheel. TimerHaptics ticks per step.
//   - preset chips 1m 3m 5m 10m, plus a "More" menu with the original longer presets; a chip
//     sets the wheels (applyPreset, as in the original) — the play button starts the timer.
//   - a round accent play button (and an × when there is a timer list to return to).
//   The last started duration is remembered (UserDefaults "nookTimerLastDuration").
// timer pass (2026-10-20, iOS Clock / Control Center, docs/ios-timer-reference.md):
//   - chips: the Recents (NookTimersStore.recents, newest first) and then presets, four in all; a
//     chip sets the wheels (and the label of a recent). The "…" menu starts a recent directly (like
//     the iOS Recents list's play buttons) and lists the presets;
//   - an optional label field (iOS "Label"; the timer shows "Timer" without one);
//   - a round green start button (iOS Start) and a grey × when there is a timer to return to.
// timer presets (2026-10-20, user request): the chips are the five preset slots of
//   Settings ▸ Nook ▸ Widgets ▸ Timer (TimerWidgetSettings.presets, read live; a 0 s slot is hidden);
//   a chip sets the wheels and, when the preset has one, the label. The "…" menu now only lists the
//   Recents (start directly) and is hidden when "Show Recents" is off or there are none.
struct TimerCreatorView: View {

    /// Called with the duration in seconds and the label when the start button is pressed.
    var onStart: (Int, String) -> Void
    /// When set, an × button closes the creator (back to the running timers).
    var onCancel: (() -> Void)? = nil
    var store: NookTimersStore = .shared
    /// Debug snapshots only: use these settings instead of the stored ones.
    var settingsOverride: TimerWidgetSettings? = nil

    @StoredSetting(.timerWidgetSettings) private var storedSettings
    private var settings: TimerWidgetSettings { settingsOverride ?? storedSettings }

    @AppStorage("nookTimerLastDuration") private var lastDuration: Int = 300

    @State private var hours: Int = 0
    @State private var minutes: Int = 5
    @State private var seconds: Int = 0
    @State private var label: String = ""
    @State private var loaded = false

    // hours * 3600 + minutes * 60 + seconds
    var totalSeconds: Int {
        hours * 3600 + minutes * 60 + seconds
    }

    /// The preset slots with a duration, in order (the chips).
    static func chipPresets(_ settings: TimerWidgetSettings) -> [TimerPreset] {
        TimerPreset.normalized(settings.presets).filter { $0.seconds > 0 }
    }

    private var chips: [TimerPreset] { Self.chipPresets(settings) }
    private var menuRecents: [NookTimersStore.Recent] { settings.showRecents ? store.recents : [] }

    var body: some View {
        VStack(spacing: NookWidgetMetrics.spacing) {
            HStack(spacing: 0) {
                TimerWheelColumn(value: $hours, range: 0...23, unit: .hours)
                separator
                TimerWheelColumn(value: $minutes, range: 0...59, unit: .minutes)
                separator
                TimerWheelColumn(value: $seconds, range: 0...59, unit: .seconds)
            }
            .frame(maxWidth: .infinity)

            if !chips.isEmpty || !menuRecents.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        NookChip(isSelected: totalSeconds == chip.seconds, horizontalPadding: 2, action: { apply(chip) }) {
                            Text(verbatim: TimerRowView.shortDuration(chip.seconds))
                        }
                        .frame(maxWidth: .infinity)
                        .help(chip.label.isEmpty
                              ? Text(verbatim: TimerRowView.shortDuration(chip.seconds))
                              : Text(verbatim: "\(chip.label) — \(TimerRowView.shortDuration(chip.seconds))"))
                        .accessibilityLabel(chipAccessibilityLabel(chip))
                    }
                    if chips.isEmpty { Spacer(minLength: 0) }
                    if !menuRecents.isEmpty { moreMenu }
                }
            }

            HStack(spacing: 6) {
                TextField("Label", text: $label)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: NookWidgetMetrics.controlHeight)
                    .background(Capsule().fill(.quinary))
                    .onSubmit(start)
                    .accessibilityLabel(Text("Label"))
                if let onCancel {
                    TimerRoundButton(systemImage: "xmark", label: Text("Close"), diameter: 28, action: onCancel)
                }
                TimerRoundButton(systemImage: "play.fill", label: Text("Start"), diameter: 30, tint: .green, action: start)
                    .disabled(totalSeconds == 0)
                    .opacity(totalSeconds == 0 ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            #if DEBUG
            TimerPresetsGalleryDebug.install()
            #endif
            guard !loaded else { return }
            loaded = true
            let total = max(lastDuration, 0)
            hours = min(total / 3600, 23)
            minutes = (total % 3600) / 60
            seconds = total % 60
        }
    }

    private var moreMenu: some View {
        Menu {
            Section("Recents") {
                ForEach(menuRecents) { recent in
                    Button {
                        TimerHaptics.shared.lock()
                        store.start(recent)
                        onCancel?()
                    } label: {
                        Label {
                            Text(verbatim: recent.label.isEmpty
                                 ? TimerRowView.shortDuration(recent.seconds)
                                 : "\(TimerRowView.shortDuration(recent.seconds))  \(recent.label)")
                        } icon: { Image(systemName: "play.fill") }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 22, height: 22)
        .nookGlass(in: Circle(), interactive: true)
        .help(Text("Recents"))
        .accessibilityLabel(Text("Recents"))
    }

    private func chipAccessibilityLabel(_ chip: TimerPreset) -> Text {
        let duration = Duration.seconds(chip.seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        return chip.label.isEmpty ? Text(verbatim: duration) : Text(verbatim: "\(chip.label), \(duration)")
    }

    private func start() {
        guard totalSeconds > 0 else { return }
        lastDuration = totalSeconds
        TimerHaptics.shared.lock()
        onStart(totalSeconds, label.trimmingCharacters(in: .whitespacesAndNewlines))
        label = ""
    }

    /// ":" between two wheel columns, aligned with the current values.
    private var separator: some View {
        Text(verbatim: ":")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 1)
            .accessibilityHidden(true)
    }

    private func apply(_ chip: TimerPreset) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78, blendDuration: 0)) {
            hours = min(chip.seconds / 3600, 23)
            minutes = (chip.seconds % 3600) / 60
            seconds = chip.seconds % 60
        }
        if !chip.label.isEmpty { label = chip.label }
        TimerHaptics.shared.tick(.minutes)
    }

    // withAnimation(.spring(response:0.35, dampingFraction:0.78, blendDuration:0))
    func applyPreset(minutes total: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78, blendDuration: 0)) {
            hours = min(total / 60, 23)
            minutes = total % 60
            seconds = 0
        }
        TimerHaptics.shared.tick(.minutes)
    }

    static func presetLabel(_ minutes: Int) -> String {
        if minutes >= 60 {
            return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Wheel column

/// One wheel of the creator: previous / current / next value; the current one sits on a glass
/// pill. Scroll, drag or click the neighbours to change it; values wrap around.
struct TimerWheelColumn: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: TimerWheelUnit

    @State private var hovering = false
    @State private var dragBase: Int? = nil
    @State private var scrollMonitor: Any? = nil
    @State private var scrollAccumulator: CGFloat = 0

    private var suffix: String {
        switch unit {
        case .hours: return "h"
        case .minutes: return "m"
        case .seconds: return "s"
        }
    }

    private var accessibilityName: Text {
        switch unit {
        case .hours: return Text("Hours")
        case .minutes: return Text("Minutes")
        case .seconds: return Text("Seconds")
        }
    }

    private func wrapped(_ v: Int) -> Int {
        let count = range.count
        return ((v - range.lowerBound) % count + count) % count + range.lowerBound
    }

    var body: some View {
        VStack(spacing: 0) {
            neighbour(wrapped(value - 1)) { step(-1) }
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(format: "%02d", value))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText(value: Double(value)))
                Text(verbatim: suffix)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 28)
            .nookGlass(in: Capsule())
            neighbour(wrapped(value + 1)) { step(1) }
        }
        .frame(width: 44)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { drag in
                    let base = dragBase ?? value
                    if dragBase == nil { dragBase = base }
                    let target = wrapped(base - Int((drag.translation.height / 10).rounded()))
                    if target != value { set(target) }
                }
                .onEnded { _ in dragBase = nil }
        )
        .onHover { inside in
            hovering = inside
            inside ? installScrollMonitor() : removeScrollMonitor()
        }
        .onDisappear { removeScrollMonitor() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(Text(verbatim: "\(value)"))
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    private func neighbour(_ v: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(String(format: "%02d", v))
                .font(.system(.caption, design: .rounded).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 42, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ delta: Int) {
        set(wrapped(value + delta))
    }

    private func set(_ newValue: Int) {
        withAnimation(.snappy(duration: 0.18)) { value = newValue }
        TimerHaptics.shared.tick(unit)
    }

    /// Scroll-wheel / trackpad scrolling over the column (SwiftUI on macOS 14 has no scroll-wheel
    /// modifier): a local monitor while the pointer is inside; consumed events do not scroll the
    /// widget row. Only vertical movement is consumed: horizontal swipes (the widget pager) and
    /// events without vertical movement (a gesture's `.ended` / `.cancelled`, momentum ends) pass
    /// through, so a swipe that crosses the column still finishes.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard hovering else { return event }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { scrollAccumulator = 0 }
            guard event.scrollingDeltaY != 0, abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
                return event
            }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
            scrollAccumulator += delta
            while abs(scrollAccumulator) >= 1 {
                // scrollingDeltaY is in content direction: content moving up (< 0) reveals the
                // next value, like a wheel
                step(scrollAccumulator > 0 ? -1 : 1)
                scrollAccumulator -= scrollAccumulator > 0 ? 1 : -1
            }
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        scrollAccumulator = 0
    }
}
