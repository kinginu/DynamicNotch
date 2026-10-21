// F7 (2026-10-21): the Accessibility (AXUIElement) side of the AirPods listening-mode control
// (AirPodsNoiseControl.swift, docs/airpods.md). Blocking; AirPodsNoiseControlService runs it on a
// background serial queue, one request at a time.
//
// One request:
//   1. Find the Sound menu extra by its AXIdentifier `com.apple.menuextra.sound` (locale-independent;
//      verified on this Mac) in Control Center's AXExtrasMenuBar — or in com.apple.MenuBarAgent's
//      tree, which owns the menu-bar items on macOS 27 according to open-source tools.
//   2. AXPress it and wait (≤ 1.2 s) until Control Center exposes one more AXWindow (the menu). An
//      error from the press is not trusted: AXPress on a menu extra often reports
//      kAXErrorCannotComplete while the menu is still opening, so the window count decides.
//   3. Snapshot the window's tree (bounded walk) and parse it (ControlCenterSoundMenuParser). If the
//      AirPods' section is collapsed, press its disclosure triangle once and snapshot again.
//   4. set: AXPress the mode's checkbox (if it is not already selected) and re-read until the
//      selection moved (≤ 0.8 s).
//   5. Always close the menu, on every exit path (the close is deferred before the first press):
//      - if the menu was not seen opening, watch ≤ 1 s for a late one (slow Control Center);
//      - close with AXCancel on the menu window once (not a toggle), then by
//        pressing the Sound item again; after each attempt wait ≤ 1 s for the window to actually
//        leave AXWindows (it stays listed during its fade) before trying again; give up after 4 s.
// Nothing else is pressed: the device rows themselves are never pressed (that would switch the
// output), and nothing is done while the screen is locked.
import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

final class AirPodsControlCenterDriver: AirPodsListeningModeDriving, @unchecked Sendable {
    static let soundItemIdentifier = "com.apple.menuextra.sound"
    static let controlCenterBundleID = "com.apple.controlcenter"
    static let menuBarAgentBundleID = "com.apple.MenuBarAgent"

    var openTimeout: TimeInterval = 1.2
    var settleTimeout: TimeInterval = 0.8
    var pollInterval: TimeInterval = 0.04
    /// How long `close` watches for a menu that opens after `openTimeout` (it was not seen opening).
    var lateOpenGrace: TimeInterval = 1.0
    /// After a close attempt: how long to wait for the window to leave AXWindows before retrying.
    var closeConfirmTimeout: TimeInterval = 1.0
    /// Overall limit of the close loop.
    var closeTimeout: TimeInterval = 4.0

    func perform(_ request: AirPodsListeningModeRequest) -> Result<AirPodsListeningModeReading, AirPodsNoiseControlError> {
        guard AXIsProcessTrusted() else { return .failure(.accessibilityNotGranted) }
        guard !Self.screenIsLocked() else { return .failure(.screenLocked) }
        guard let cc = Self.application(Self.controlCenterBundleID) else { return .failure(.soundMenuNotFound) }
        AXUIElementSetMessagingTimeout(cc, 1.0)
        guard let soundItem = Self.soundMenuItem() else { return .failure(.soundMenuNotFound) }

        let baseline = Self.windows(of: cc).count
        var opened = false
        // Registered before the press: every exit path below closes the menu, including a press
        // that reported an error but opened the menu anyway, and a menu that opens late.
        defer { close(soundItem, cc: cc, baseline: baseline, opened: opened) }
        _ = Self.press(soundItem)   // the window count, not the press result, says whether it opened

        guard let window = waitFor(timeout: openTimeout, { Self.windows(of: cc).count > baseline ? Self.windows(of: cc).last : nil })
        else { return .failure(.menuDidNotOpen) }
        opened = true

        let deviceName: String
        switch request {
        case .read(let name), .set(_, let name): deviceName = name
        }

        // The device list fills in after the window appears.
        var snap = waitFor(timeout: settleTimeout, {
            let s = Snapshot(window, deviceName: deviceName)
            return s.layout.target != nil && !s.layout.modes.isEmpty ? s : nil
        }) ?? Snapshot(window, deviceName: deviceName)

        guard let target = snap.layout.target else { return .failure(.deviceNotInMenu) }
        if snap.layout.modes.isEmpty, let d = snap.layout.disclosureIndex, !snap.layout.disclosureExpanded {
            _ = Self.press(snap.elements[d])
            if let expanded = waitFor(timeout: settleTimeout, {
                let s = Snapshot(window, deviceName: deviceName)
                return s.layout.modes.isEmpty ? nil : s
            }) { snap = expanded }
        }
        guard target.isSelected else { return .failure(.deviceNotOutput) }
        guard !snap.layout.modes.isEmpty else { return .failure(.modesNotFound) }

        var reading = AirPodsListeningModeReading(deviceName: target.name, mode: snap.layout.selectedMode,
                                                  available: snap.layout.availableModes)
        guard case .set(let wanted, _) = request else { return .success(reading) }
        guard let item = snap.layout.item(for: wanted) else { return .failure(.modeUnavailable(wanted)) }
        if item.isSelected { return .success(reading) }

        guard Self.press(snap.elements[item.index]) else { return .failure(.pressFailed) }
        if let after = waitFor(timeout: settleTimeout, {
            let s = Snapshot(window, deviceName: deviceName)
            return s.layout.selectedMode == wanted ? s : nil
        }) {
            reading.mode = after.layout.selectedMode
            reading.available = after.layout.availableModes
        } else {
            // Pressed, but the checkbox did not read back as selected in time: report what it says now.
            let now = Snapshot(window, deviceName: deviceName)
            reading.mode = now.layout.selectedMode
        }
        return .success(reading)
    }

    // MARK: Menu handling

    /// Closes the Sound menu if it is (or becomes) open. `opened`: the menu was seen opening.
    private func close(_ item: AXUIElement, cc: AXUIElement, baseline: Int, opened: Bool) {
        let isOpen = { Self.windows(of: cc).count > baseline }
        if !opened {
            // a slow Control Center can show the menu after openTimeout: catch it here
            guard waitFor(timeout: lateOpenGrace, { isOpen() ? true : nil }) != nil else { return }
        }
        // a close press during the open animation is ignored
        Thread.sleep(forTimeInterval: 0.15)
        let deadline = Date().addingTimeInterval(closeTimeout)
        var triedCancel = false
        while isOpen(), Date() < deadline {
            // First AXCancel on the menu window (not a toggle, so it cannot reopen the menu); if the
            // window does not take it, or it did not close the menu, press the Sound item.
            var acted = false
            if !triedCancel, let menu = Self.windows(of: cc).last {
                triedCancel = true
                acted = AXUIElementPerformAction(menu, kAXCancelAction as CFString) == .success
            }
            if !acted { _ = Self.press(item) }
            // wait for the attempt to take effect: the closing window stays in AXWindows during its
            // fade, and pressing the toggle again then would reopen the menu
            if waitFor(timeout: closeConfirmTimeout, { isOpen() ? nil : true }) != nil { return }
        }
    }

    private func waitFor<T>(timeout: TimeInterval, _ probe: () -> T?) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let value = probe() { return value }
            Thread.sleep(forTimeInterval: pollInterval)
        } while Date() < deadline
        return probe()
    }

    /// The Sound menu's tree flattened depth-first, with the elements kept for pressing.
    private struct Snapshot {
        var elements: [AXUIElement] = []
        var nodes: [ControlCenterAXNode] = []
        var layout = ControlCenterSoundMenuLayout()

        init(_ root: AXUIElement, deviceName: String) {
            var stack: [(AXUIElement, Int)] = [(root, 0)]
            while elements.count < 800, let next = stack.popLast() {
                let (element, depth) = next
                elements.append(element)
                nodes.append(ControlCenterAXNode(
                    role: AirPodsControlCenterDriver.string(element, kAXRoleAttribute) ?? "",
                    identifier: AirPodsControlCenterDriver.string(element, kAXIdentifierAttribute),
                    title: AirPodsControlCenterDriver.string(element, kAXTitleAttribute),
                    axDescription: AirPodsControlCenterDriver.string(element, kAXDescriptionAttribute),
                    value: (AirPodsControlCenterDriver.attribute(element, kAXValueAttribute) as? NSNumber)?.intValue))
                guard depth < 24 else { continue }
                stack.append(contentsOf: AirPodsControlCenterDriver.children(element).reversed().map { ($0, depth + 1) })
            }
            layout = ControlCenterSoundMenuParser.parse(nodes, deviceName: deviceName)
        }
    }

    // MARK: AX helpers

    static func application(_ bundleID: String) -> AXUIElement? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    /// The Sound menu extra: Control Center's extras menu bar (macOS 26), else MenuBarAgent's tree.
    static func soundMenuItem() -> AXUIElement? {
        for bundleID in [controlCenterBundleID, menuBarAgentBundleID] {
            guard let app = application(bundleID) else { continue }
            AXUIElementSetMessagingTimeout(app, 1.0)
            var roots: [AXUIElement] = []
            for key in ["AXExtrasMenuBar", kAXMenuBarAttribute as String] {
                if let value = attribute(app, key), CFGetTypeID(value) == AXUIElementGetTypeID() {
                    roots.append(value as! AXUIElement)
                }
            }
            if roots.isEmpty { roots = [app] }
            for root in roots {
                if let item = find(in: root, maxDepth: 4, { string($0, kAXIdentifierAttribute) == soundItemIdentifier }) {
                    return item
                }
            }
        }
        return nil
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func find(in root: AXUIElement, maxDepth: Int, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 400 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if match(element) { return element }
            if depth < maxDepth { queue.append(contentsOf: children(element).map { ($0, depth + 1) }) }
        }
        return nil
    }

    static func screenIsLocked() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
