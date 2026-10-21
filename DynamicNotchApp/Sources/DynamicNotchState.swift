import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import SwiftUI
import AppKit
import Observation

@Observable
class DynamicNotchState {
    // One state per notch window (screen), owned by WindowsManager.DisplayKit and
    //   injected as `\.dynamicNotchState`, so only the notch under the pointer opens (a single
    //   shared state opened every screen's notch at once). Views read the injected state; the few
    //   non-view call sites that used the old singleton (tray key monitor, debug hooks) use
    //   `shared`, which now resolves to the open notch, else the one under the pointer, else the
    //   main screen's. Lookups read `_mode` directly so they do not register Observation
    //   dependencies on other screens' states.
    static var perScreen: [CGDirectDisplayID: DynamicNotchState] = [:]
    private static let fallback = DynamicNotchState()

    static var shared: DynamicNotchState {
        if let open = perScreen.values.first(where: { $0._mode != .closed }) { return open }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
           let state = perScreen[screen.displayID] { return state }
        if let main = NSScreen.main, let state = perScreen[main.displayID] { return state }
        return perScreen.values.first ?? fallback
    }

    /// True when any screen's notch is in `mode` (untracked read).
    static func anyScreen(in mode: NotchMode) -> Bool {
        perScreen.values.contains { $0._mode == mode }
    }

    // A change notifies observers; setting the same value only runs the will/did-set side effects.
    var hidden: Bool {
        get {
            access(keyPath: \.hidden)
            return _hidden
        }
        set {
            if newValue != _hidden {
                withMutation(keyPath: \.hidden) {
                    self._hidden = newValue
                }
            } else {
                _hiddenWillSet(newValue)
                _hidden = newValue
                _hiddenDidSet()
            }
        }
    }

    // Hiding plays a haptic (when enabled in General settings); un-hiding cancels the pending
    //   hidden-state timer.
    private func _hiddenWillSet(_ newValue: Bool) {
        if !_hidden {
            if newValue {
                if !GeneralSettings.defaultValue.hapticFeedbackEnabled {
                    return
                }
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .generic, performanceTime: .default
                )
                return
            }
        } else {
            if newValue {
                return
            }
        }
        _hiddenTimer?.invalidate()
    }

    // When hidden (and live activities are on), runs a spring animation on the next run-loop turn.
    private func _hiddenDidSet() {
        if _hidden {
            let liveSettings = LiveActivitiesSettings.defaultValue
            if liveSettings.enabled {
                let timer = Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { [weak self] _ in
                    _ = withAnimation(.spring(response: 0.5, dampingFraction: 1.0, blendDuration: 0)) {
                        // triggers SwiftUI re-evaluation
                    }
                }
                _hiddenTimer = timer
            }
        }
    }

    var hiddenTimer: Timer? {
        get {
            access(keyPath: \.hiddenTimer)
            return _hiddenTimer
        }
        set {
            if let current = _hiddenTimer, let incoming = newValue, current === incoming {
                _hiddenTimer = newValue
                return
            }
            if _hiddenTimer == nil && newValue == nil {
                _hiddenTimer = nil
                return
            }
            withMutation(keyPath: \.hiddenTimer) {
                self._hiddenTimer = newValue
            }
        }
    }

    var indicator: Indicator? {
        get {
            access(keyPath: \.indicator)
            return _indicator
        }
        set {
            let isDifferent = !DynamicNotchState.shouldNotifyObservers(old: _indicator, new: newValue)
            if isDifferent {
                _indicatorTimer?.invalidate()
                _indicator = newValue
                _indicatorDidSet()
            } else {
                withMutation(keyPath: \.indicator) {
                    self._indicator = newValue
                }
            }
        }
    }

    // After an indicator change, runs the indicator-resize animation one second later.
    private func _indicatorDidSet() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            _ = withAnimation(.indicatorResize) {
                // triggers SwiftUI re-evaluation
            }
        }
        _indicatorTimer = timer
    }

    var indicatorTimer: Timer? {
        get {
            access(keyPath: \.indicatorTimer)
            return _indicatorTimer
        }
        set {
            if let current = _indicatorTimer, let incoming = newValue, current === incoming {
                _indicatorTimer = newValue
                return
            }
            if _indicatorTimer == nil && newValue == nil {
                _indicatorTimer = nil
                return
            }
            withMutation(keyPath: \.indicatorTimer) {
                self._indicatorTimer = newValue
            }
        }
    }

    var locked: Bool {
        get {
            access(keyPath: \.locked)
            return _locked
        }
        set {
            if newValue == _locked {
                _locked = newValue
            } else {
                withMutation(keyPath: \.locked) {
                    self._locked = newValue
                }
            }
        }
    }

    var quickPeeks: [QuickPeek]? {
        get {
            access(keyPath: \.quickPeeks)
            return _quickPeeksStorage
        }
        set {
            if let current = _quickPeeksStorage, let incoming = newValue, current == incoming {
                _quickPeeksStorage = newValue
                return
            }
            if _quickPeeksStorage == nil && newValue == nil {
                _quickPeeksStorage = nil
                return
            }
            withMutation(keyPath: \.quickPeeks) {
                self._quickPeeksStorage = newValue
            }
        }
    }

    var mode: NotchMode {
        get {
            access(keyPath: \.mode)
            return _mode
        }
        set {
            if newValue != _mode {
                withMutation(keyPath: \.mode) {
                    self._mode = newValue
                }
            }
        }
    }

    var willSelectTab: (() -> Void)?

    // --- Stored state (observed through the accessors above) ---
    private var _hidden: Bool = false
    private var _hiddenTimer: Timer? = nil

    private var _indicator: Indicator? = nil
    private var _indicatorTimer: Timer? = nil

    private var _locked: Bool = false

    private var _quickPeeksStorage: [QuickPeek]? = nil

    private var _mode: NotchMode = .closed

    // every stored property has its default value above
    init() {}

    // Switches the open notch to the Nook or the Tray (other modes are ignored): calls
    //   `willSelectTab`, remembers the choice as `preferredOpenMode`, then changes `mode`.
    func select(_ mode: NotchMode) {
        guard mode == .nook || mode == .tray else {
            return
        }

        access(keyPath: \._mode)

        let currentMode = _mode
        if currentMode != mode {
            if let callback = willSelectTab {
                callback()
            }

            DynamicNotchState.preferredOpenMode = mode

            if _mode != mode {
                withMutation(keyPath: \._mode) {
                    self._mode = mode
                }
            }
        }
    }

    // The last tab opened (.nook or .tray), persisted in UserDefaults; other modes are not stored.
    static var preferredOpenMode: NotchMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "preferredOpenMode") else {
                return .closed
            }
            return NotchMode(rawValue: raw) ?? .closed
        }
        set {
            guard newValue == .nook || newValue == .tray else { return }
            let raw: String = (newValue == .tray) ? "tray" : "nook"
            UserDefaults.standard.set(raw, forKey: "preferredOpenMode")
        }
    }

    // Resets everything: timers cancelled, not hidden, no indicator, unlocked, no quick peeks, closed.
    func cleanup() {
        _hiddenTimer?.invalidate()
        if _hiddenTimer != nil {
            _hiddenTimer = nil
        }

        _indicatorTimer?.invalidate()
        if _indicatorTimer != nil {
            _indicatorTimer = nil
        }

        if !_hidden {
            _hiddenTimer?.invalidate()
            _hidden = false
            _hiddenDidSet()
        } else {
            withMutation(keyPath: \.hidden) {
                self._hidden = false
            }
        }

        let shouldNotify = DynamicNotchState.shouldNotifyObservers(old: _indicator, new: Optional<Indicator>.none)
        if !shouldNotify {
            _indicatorTimer?.invalidate()
            _indicator = nil
            _indicatorDidSet()
        } else {
            withMutation(keyPath: \.indicator) {
                self._indicator = nil
            }
        }

        if _locked {
            withMutation(keyPath: \.locked) {
                self._locked = false
            }
        } else {
            _locked = false
        }

        if _quickPeeksStorage != nil {
            withMutation(keyPath: \.quickPeeks) {
                self._quickPeeksStorage = nil
            }
        }

        if _mode != .closed {
            withMutation(keyPath: \.mode) {
                self._mode = .closed
            }
        }
    }

    deinit {
        cleanup()
    }

    // Returns true when values are the same (no notification needed)
    private static func shouldNotifyObservers<T: Equatable>(old: T?, new: T?) -> Bool {
        return old == nil && new == nil
    }
}

// MARK: - DynamicNotchState.NotchMode

extension DynamicNotchState {
    enum NotchMode: String, Equatable, Hashable, CaseIterable {
        case closed = "closed"
        case nook = "nook"
        case tray = "tray"
        case dragging = "dragging"
    }
}

// MARK: - DynamicNotchState.QuickPeek

extension DynamicNotchState {
    struct QuickPeek: Identifiable, Equatable, Hashable {
        let id: UUID

        var title: String?

        var name: String

        var color: Color?

        var anchor: UnitPoint

        // optionals hash a 0/1 presence byte before their value
        func hash(into hasher: inout Hasher) {
            // UUID hash
            hasher.combine(id)

            // Optional title
            if let title = title {
                hasher.combine(UInt8(1))
                hasher.combine(title)
            } else {
                hasher.combine(UInt8(0))
            }

            // Non-optional name
            hasher.combine(name)

            // Optional color
            if let color = color {
                hasher.combine(UInt8(1))
                hasher.combine(color)
            } else {
                hasher.combine(UInt8(0))
            }

            // Non-optional anchor
            hasher.combine(anchor)
        }

        static func == (lhs: QuickPeek, rhs: QuickPeek) -> Bool {
            // UUID
            guard lhs.id == rhs.id else { return false }

            // Optional title
            switch (lhs.title, rhs.title) {
            case (.none, .none): break
            case (.some, .none), (.none, .some): return false
            case (.some(let l), .some(let r)): guard l == r else { return false }
            }

            // Non-optional name
            guard lhs.name == rhs.name else { return false }

            // Optional color
            switch (lhs.color, rhs.color) {
            case (.none, .none): break
            case (.some, .none), (.none, .some): return false
            case (.some(let l), .some(let r)): guard l == r else { return false }
            }

            // Non-optional anchor
            guard lhs.anchor == rhs.anchor else { return false }

            return true
        }
    }
}
