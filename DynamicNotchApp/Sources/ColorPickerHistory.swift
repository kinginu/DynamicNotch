// Color Picker widget model (2026-10-20): picked colours, their text formats, WCAG contrast,
// the screen sampler and the recent-colours history.
//
// Sampling: `NSColorSampler` (the system loupe, macOS 10.15+). It needs no Screen Recording
// permission. The notch would close as soon as the pointer leaves it, so the sampling session is
// wrapped in `NotchInteractionMonitor.begin()/end()` (NotchHover.swift): the
// notch stays open while the loupe is up and the result appears in the widget.
//
// Colour values are sRGB (the sampled colour is converted with `usingColorSpace(.sRGB)`; Display P3
// colours outside sRGB are clamped to 0…1), which is what #RRGGBB / rgb() / hsl() and SwiftUI's
// `Color(red:green:blue:)` mean.
//
// Persistence (local only): `~/Library/Application Support/<bundle id>/ColorPickerHistory.json`
// (file mode 0600), newest first, at most `ColorPickerWidgetSettings.historyLimit` entries.
//
// `PickedColor` (formats, HSL, WCAG contrast) and the history rules are pure Foundation in
// ColorPickerModel.swift (tested there); this file adds the AppKit / SwiftUI side.
import AppKit
import Foundation
import Observation
import SwiftUI

extension PickedColor {
    /// nil when the colour cannot be expressed in sRGB (pattern colours etc.).
    init?(_ color: NSColor) {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

@MainActor
@Observable
final class ColorPickerHistoryStore {
    static let shared = ColorPickerHistoryStore()

    /// Newest first; `colors.first` is the current colour.
    private(set) var colors: [PickedColor] = []
    /// The system loupe is up.
    private(set) var isSampling = false
    /// Last colour copied to the pasteboard (feedback in the widget).
    private(set) var lastCopied: (id: UUID, format: ColorCopyFormat, date: Date)?

    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var sampler: NSColorSampler?
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored private let ioQueue = DispatchQueue(label: "dynamicnotch.color-picker-history.io", qos: .utility)
    #if DEBUG
    /// Preview data (DEBUG snapshots): nothing is loaded or saved while set.
    @ObservationIgnored var isPreview = false
    #endif

    private init() {}

    private var settings: ColorPickerWidgetSettings { SettingsStore[.colorPickerWidgetSettings] }

    var current: PickedColor? { colors.first }

    /// Loads the history once.
    func start() {
        guard !loaded else { return }
        loaded = true
        #if DEBUG
        if isPreview { return }
        #endif
        load()
    }

    // MARK: Sampling

    /// Shows the system colour loupe; the picked colour becomes the current one (and is copied
    /// when `copyOnPick` is on). Escape cancels.
    func pick() {
        guard !isSampling else { return }
        start()
        isSampling = true
        NotchInteractionMonitor.begin()
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            // called on the main thread
            MainActor.assumeIsolated {
                guard let self else { NotchInteractionMonitor.end(); return }
                self.isSampling = false
                self.sampler = nil
                NotchInteractionMonitor.end()
                guard let color, let picked = PickedColor(color) else { return }
                self.add(picked)
                if self.settings.copyOnPick { self.copy(picked) }
            }
        }
    }

    // MARK: History

    func add(_ color: PickedColor) {
        start()
        colors = ColorPickerHistoryList.adding(color, to: colors, limit: settings.historyLimit)
        scheduleSave()
    }

    /// Makes `color` the current one (moves it to the front) and copies it.
    func select(_ color: PickedColor) {
        let (list, moved) = ColorPickerHistoryList.selecting(color, in: colors, date: Date())
        colors = list
        copy(moved)
        scheduleSave()
    }

    func remove(_ color: PickedColor) {
        colors.removeAll { $0.id == color.id }
        scheduleSave()
    }

    func clear() {
        colors = []
        scheduleSave()
    }

    /// Applies a lowered history limit.
    func trim() {
        let trimmed = ColorPickerHistoryList.trimmed(colors, limit: settings.historyLimit)
        guard trimmed.count != colors.count else { return }
        colors = trimmed
        scheduleSave()
    }

    // MARK: Pasteboard

    func copy(_ color: PickedColor, format: ColorCopyFormat? = nil) {
        let s = settings
        let format = format ?? s.format
        let text = color.formatted(format, uppercaseHex: s.uppercaseHex)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastCopied = (color.id, format, Date())
    }

    // MARK: Persistence

    nonisolated static let historyURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "DynamicNotch", isDirectory: true)
            .appendingPathComponent("ColorPickerHistory.json")
    }()

    private func load() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let decoded = try? JSONDecoder().decode([PickedColor].self, from: data) else { return }
        colors = ColorPickerHistoryList.trimmed(decoded, limit: settings.historyLimit)
    }

    private func scheduleSave() {
        #if DEBUG
        if isPreview { return }
        #endif
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveNow() {
        guard let data = try? JSONEncoder().encode(colors) else { return }
        let url = Self.historyURL
        ioQueue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    #if DEBUG
    /// DEBUG snapshots: replaces the in-memory history (never saved).
    func setPreviewColors(_ list: [PickedColor]) {
        isPreview = true
        loaded = true
        colors = list
        lastCopied = nil
    }
    #endif
}
