// Capture widget (2026-10-20): Area / Window / Screen screenshots and a screen recording,
// through CaptureManager (/usr/sbin/screencapture). Layout (4 cells = 200 pt × 202 pt):
//   header      "Capture" + destination menu (Desktop / Clipboard / Tray)
//   tiles       Area · Window · Screen
//   record row  Record Screen | ● 0:12 … Stop | Saving… | Starting in 3… Cancel
//   delay chips Off · 3 s · 10 s
//   footer      Screen Recording hint (with Allow) or the last result ("Saved to Desktop")
// Also: the closed-notch recording indicator (red dot | elapsed time beside the camera housing).
import SwiftUI
import AppKit

struct CaptureWidgetView: View {
    @State private var manager = CaptureManager.shared
    @StoredSetting(.captureWidgetSettings) private var settings
    @Environment(\.dynamicNotchState) private var notchState

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.stackSpacing) {
            header
            tiles
            recordRow
            delayRow
            footer
        }
        .nookWidgetFrame()
        .onAppear { manager.refreshPermission() }
        .nookWidgetGalleryHook()
    }

    // MARK: Header

    private var header: some View {
        NookWidgetHeader("Capture", systemImage: "camera.viewfinder") {
            Menu {
                Picker("Save to", selection: $settings.destination) {
                    ForEach(CaptureDestination.allCases) { d in
                        Label(d.title, systemImage: d.systemImage).tag(d)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: settings.destination.systemImage)
                    Text(settings.destination.title)
                }
                .font(.caption.weight(.medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .controlSize(.mini)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize()
            .help(String(localized: "Where captures are saved"))
        }
        .frame(height: 18)
    }

    // MARK: Screenshot tiles

    private var tiles: some View {
        HStack(spacing: 6) {
            ForEach([CaptureKind.area, .window, .screen]) { kind in
                Button {
                    manager.start(kind, notch: notchState)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 18, weight: .regular))
                            .symbolRenderingMode(.hierarchical)
                        Text(kind.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous))
                    .nookGlass(in: RoundedRectangle(cornerRadius: NookWidgetMetrics.rowCornerRadius, style: .continuous),
                               interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(manager.isBusy)
                .opacity(manager.isBusy ? 0.5 : 1)
                .help(help(for: kind))
                .accessibilityLabel(Text(help(for: kind)))
            }
        }
    }

    private func help(for kind: CaptureKind) -> String {
        switch kind {
        case .area:      return String(localized: "Capture a selected area")
        case .window:    return String(localized: "Capture a window")
        case .screen:    return String(localized: "Capture the main screen")
        case .recording: return String(localized: "Record the main screen")
        }
    }

    // MARK: Record row

    @ViewBuilder
    private var recordRow: some View {
        Group {
            switch manager.phase {
            case .recording(let started):
                HStack(spacing: 6) {
                    CaptureRecordingDot()
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(CaptureElapsed.format(context.date.timeIntervalSince(started)))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    Button {
                        manager.stopRecording()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .controlSize(.small)
                    .nookButtonStyle(prominent: true)
                    .tint(.red)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 30)
                .nookCard(cornerRadius: NookWidgetMetrics.rowCornerRadius)
            case .stopping:
                statusRow {
                    ProgressView().controlSize(.small)
                    Text("Saving recording…")
                }
            case .countdown(let kind, let fireDate):
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let left = max(Int(ceil(fireDate.timeIntervalSince(context.date))), 0)
                        Text(String(localized: "\(kind.title) in \(left) s"))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button("Cancel") { manager.cancelCountdown() }
                        .controlSize(.small)
                        .nookButtonStyle()
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 30)
                .nookCard(cornerRadius: NookWidgetMetrics.rowCornerRadius)
            case .capturing(let kind):
                statusRow {
                    Image(systemName: kind.systemImage).foregroundStyle(.secondary)
                    Text(kind == .screen ? String(localized: "Capturing…") : String(localized: "Press Esc to cancel"))
                }
            case .idle:
                Button {
                    manager.start(.recording, notch: notchState)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.red)
                        Text("Record Screen")
                        Spacer(minLength: 0)
                        if settings.recordingLimitSeconds > 0 {
                            Text(CaptureElapsed.format(TimeInterval(settings.recordingLimitSeconds)))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .contentShape(Capsule())
                    .nookGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .help(help(for: .recording))
            }
        }
        .frame(height: 30)
    }

    private func statusRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) { content() }
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .nookCard(cornerRadius: NookWidgetMetrics.rowCornerRadius)
    }

    // MARK: Delay chips

    private var delayRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(String(localized: "Delay before capturing"))
            ForEach(CaptureWidgetSettings.delayChoices, id: \.self) { seconds in
                NookChip(isSelected: settings.delaySeconds == seconds, horizontalPadding: 4) {
                    settings.delaySeconds = seconds
                } label: {
                    Text(seconds == 0 ? String(localized: "No delay") : String(localized: "\(seconds) s"))
                }
            }
        }
        .disabled(manager.isBusy)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if !manager.hasScreenRecordingPermission {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Needs Screen Recording access")
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 2)
                Button("Allow") { manager.requestPermission() }
                    .controlSize(.mini)
                    .nookButtonStyle()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if let message = manager.lastMessage {
            NookWidgetFootnote(text: message, systemImage: "checkmark.circle")
                .transition(.opacity)
        }
    }
}

// MARK: - Shared pieces

enum CaptureElapsed {
    /// 0:07, 1:05, 1:02:03.
    static func format(_ interval: TimeInterval) -> String {
        let s = max(Int(interval), 0)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Pulsing red recording dot.
struct CaptureRecordingDot: View {
    var diameter: CGFloat = 8
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: diameter, height: diameter)
            .opacity(dim ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
            .accessibilityLabel(Text("Recording"))
    }
}

// MARK: - Closed-notch indicator

/// Red dot | elapsed time beside the camera housing while a recording runs and no other live
/// activity holds the closed notch (LiveActivities/ClosedNotchActivitiesView.swift adds the width and
/// this view; NotchView.closedNotchFootprint widens the closed notch for it).
struct CaptureClosedNotchIndicator: View {
    let notchSize: CGSize

    /// Recording, and live activities are on ("Show live activities in the closed notch"; the
    /// observed snapshot, so the notch reacts when the switch changes).
    @MainActor private static var allowed: Bool {
        CaptureManager.shared.isRecording && LiveActivityCenter.shared.liveSettings.enabled
    }

    /// Extra width on each side of the hardware notch (0 unless recording with no other activity).
    @MainActor static func extraSideWidth(activity: LiveActivity?, notchHeight: CGFloat) -> CGFloat {
        guard activity == nil, allowed else { return 0 }
        return max(notchHeight, 24) + 20
    }

    /// True when the closed notch must be widened for the indicator.
    @MainActor static var isShown: Bool { allowed }

    var body: some View {
        let manager = CaptureManager.shared
        let side = Self.extraSideWidth(activity: nil, notchHeight: notchSize.height)
        if manager.isRecording, side > 0 {
            HStack(spacing: 0) {
                CaptureRecordingDot(diameter: 9)
                    .padding(.leading, ClosedNotchActivityLayout.outerInset)
                    .frame(width: side, height: notchSize.height, alignment: .leading)
                Color.clear
                    .frame(width: notchSize.width, height: notchSize.height)
                Group {
                    if let started = manager.recordingStart {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text(CaptureElapsed.format(context.date.timeIntervalSince(started)))
                        }
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.trailing, ClosedNotchActivityLayout.outerInset)
                .frame(width: side, height: notchSize.height, alignment: .trailing)
            }
            .frame(height: notchSize.height)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}
