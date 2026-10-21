// Menu Bar widget (2026-10-20): the menu bar items hidden behind our separator, shown inside
// the open notch as live images (MenuBarItemsManager). Click = left click on the real item,
// right-click / control-click = right click. Degrades to names + app icons without Screen
// Recording, and to "show the items in the menu bar" without Accessibility.
import SwiftUI
import AppKit

/// Fixed data for the offscreen previews (DEBUG) — nil in the app.
struct MenuBarItemsPreviewState {
    var items: [MenuBarItem]
    var images: [CGWindowID: CGImage] = [:]
    var screenRecording = true
    var accessibility = true
    var separatorActive = true
    var revealed = false
    var scale: CGFloat = 2
}

struct MenuBarItemsWidgetView: View {
    var preview: MenuBarItemsPreviewState? = nil

    @StoredSetting(.menuBarItemsWidgetSettings) private var settings
    @State private var manager = MenuBarItemsManager.shared

    private var items: [MenuBarItem] { preview?.items ?? manager.hiddenItems }
    private var images: [CGWindowID: CGImage] { preview?.images ?? manager.images }
    private var screenRecording: Bool { preview?.screenRecording ?? manager.screenRecordingGranted }
    private var accessibility: Bool { preview?.accessibility ?? manager.accessibilityGranted }
    private var separatorActive: Bool { preview?.separatorActive ?? manager.separatorActive }
    private var revealed: Bool { preview?.revealed ?? manager.isRevealed }
    private var scale: CGFloat { preview?.scale ?? manager.displayScale }
    private var showImages: Bool { settings.showItemImages && screenRecording }

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if separatorActive { permissionBanner }
        }
        .nookWidgetFrame()
        .onAppear { if preview == nil { manager.widgetAppeared() } }
        .onDisappear { if preview == nil { manager.widgetDisappeared() } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "menubar.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Hidden Items")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !items.isEmpty {
                Text("\(items.count)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if separatorActive {
                NookRoundIconButton(
                    systemImage: revealed ? "eye.slash" : "eye",
                    label: revealed ? Text("Hide in Menu Bar") : Text("Show hidden items"),
                    diameter: 22
                ) {
                    if preview == nil { manager.setShowHiddenItems(!settings.showHiddenItems) }
                }
            }
        }
        .frame(height: 22)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !separatorActive {
            NookWidgetEmptyState(
                systemImage: "menubar.rectangle",
                title: String(localized: "Hiding is off"),
                message: String(localized: "Turn it on to keep menu bar items here instead of in the menu bar."),
                actionTitle: String(localized: "Turn On")
            ) {
                guard preview == nil else { return }
                settings.hidingEnabled = true
                manager.applySettings()
            }
        } else if items.isEmpty {
            NookWidgetEmptyState(
                systemImage: "command",
                title: String(localized: "No hidden items"),
                message: revealed
                    ? String(localized: "Hold ⌘ and drag menu bar items to the left of the ‹ separator to hide them here.")
                    : String(localized: "Show the separator, then hold ⌘ and drag menu bar items to its left."),
                actionTitle: revealed ? nil : String(localized: "Show Separator")
            ) {
                if preview == nil { manager.setShowHiddenItems(true) }
            }
        } else if showImages {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 120), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        MenuBarItemTile(item: item, image: images[item.windowID], scale: scale,
                                        flagged: isAlwaysShown(item), compact: false, onClick: click)
                    }
                }
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        MenuBarItemTile(item: item, image: nil, scale: scale,
                                        flagged: isAlwaysShown(item), compact: true, onClick: click)
                    }
                }
            }
        }
    }

    private func isAlwaysShown(_ item: MenuBarItem) -> Bool {
        item.bundleID.map(settings.alwaysShownBundleIDs.contains) ?? false
    }

    private func click(_ item: MenuBarItem, _ right: Bool) {
        guard preview == nil else { return }
        manager.activate(item, rightClick: right)
    }

    // MARK: Permissions

    @ViewBuilder
    private var permissionBanner: some View {
        if settings.showItemImages && !screenRecording {
            banner(systemImage: "rectangle.dashed.badge.record",
                   text: String(localized: "Allow Screen Recording to see item images."),
                   action: String(localized: "Allow")) { manager.requestScreenRecording() }
        } else if !accessibility && !items.isEmpty {
            banner(systemImage: "hand.tap",
                   text: String(localized: "Allow Accessibility to click items from here."),
                   action: String(localized: "Allow")) { manager.requestAccessibility() }
        }
    }

    private func banner(systemImage: String, text: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action) { if preview == nil { perform() } }
                .controlSize(.mini)
                .nookButtonStyle()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .nookCard(cornerRadius: NookWidgetMetrics.rowCornerRadius)
    }
}

/// One hidden item: its captured image (or app icon + name), with click forwarding.
struct MenuBarItemTile: View {
    let item: MenuBarItem
    let image: CGImage?
    let scale: CGFloat
    var flagged: Bool
    var compact: Bool
    let onClick: (MenuBarItem, Bool) -> Void

    @State private var hovering = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 6) {
                    appIcon.frame(width: 16, height: 16)
                    Text(item.appName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if flagged { flagBadge }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
            } else {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image {
                            Image(decorative: image, scale: scale)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: item.frame.width, maxHeight: 26)
                        } else {
                            appIcon.frame(width: 18, height: 18)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                    if flagged { flagBadge.padding(2) }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous)
                .fill(tileFill)
        )
        .contentShape(RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous))
        .overlay(MouseButtonCatcher(toolTip: item.appName) { right in onClick(item, right) })
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.appName))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onClick(item, false) }
    }

    /// Item images are drawn for the menu bar's appearance, not the notch's: dark images (a light
    /// menu bar) get a light tile, light images a dark tile, so they stay visible in any scheme.
    private var tileFill: AnyShapeStyle {
        if let image {
            let lum = MenuBarItemsManager.luminance(image)
            if lum < 0.35 { return AnyShapeStyle(Color.white.opacity(hovering ? 0.95 : 0.8)) }
            if lum > 0.65 { return AnyShapeStyle(Color.black.opacity(hovering ? 0.75 : 0.6)) }
        }
        return hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary)
    }

    private var flagBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.orange)
            .help(String(localized: "Set to always show in the menu bar"))
    }

    @ViewBuilder
    private var appIcon: some View {
        if let id = item.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "menubar.dock.rectangle")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}

/// Transparent overlay that reports left (false) / right or control-left (true) mouse clicks and
/// carries the tooltip (SwiftUI's `.help` does not reach through an AppKit overlay).
private struct MouseButtonCatcher: NSViewRepresentable {
    var toolTip: String
    var onClick: (Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onClick = onClick
        view.toolTip = toolTip
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onClick = onClick
        view.toolTip = toolTip
    }

    final class CatcherView: NSView {
        var onClick: ((Bool) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            onClick?(event.modifierFlags.contains(.control))
        }
        override func rightMouseDown(with event: NSEvent) {}
        override func rightMouseUp(with event: NSEvent) { onClick?(true) }
    }
}
