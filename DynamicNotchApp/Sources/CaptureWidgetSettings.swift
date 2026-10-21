// Settings of the Capture widget (2026-10-20). Key "captureWidgetSettings"
// (declared at the end of this file; pattern: SettingsUI/SettingsDecoding.swift).
import Foundation

/// Where a screenshot / recording goes.
enum CaptureDestination: String, Codable, CaseIterable, Hashable, Identifiable {
    case desktop
    case clipboard
    case tray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop:   return String(localized: "Desktop")
        case .clipboard: return String(localized: "Clipboard")
        case .tray:      return String(localized: "Tray")
        }
    }

    var systemImage: String {
        switch self {
        case .desktop:   return "menubar.dock.rectangle"
        case .clipboard: return "doc.on.clipboard"
        case .tray:      return "tray"
        }
    }
}

/// Image format of screenshots (`screencapture -t`).
enum CaptureImageFormat: String, Codable, CaseIterable, Hashable, Identifiable {
    case png, jpg, heic

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

struct CaptureWidgetSettings: Preferences, WidgetPrefs, Codable, Equatable, Hashable {
    var destination: CaptureDestination = .desktop
    /// File name without extension. Tokens: {kind} (Screenshot / Screen Recording), {date}
    /// (yyyy-MM-dd), {time} (HH.mm.ss).
    var filenamePattern: String = CaptureWidgetSettings.defaultPattern
    /// Seconds to wait (with the notch closed) before a capture starts.
    var delaySeconds: Int = 0
    var imageFormat: CaptureImageFormat = .png
    /// Play the shutter sound (off = `screencapture -x`).
    var playSounds: Bool = true
    /// Include the window shadow in window captures (off = `-o`).
    var windowShadow: Bool = true
    /// Show clicks in screen recordings (`-k`).
    var showClicks: Bool = false
    /// Stop a recording automatically after this many seconds (`-V`; 0 = until stopped).
    var recordingLimitSeconds: Int = 0
    /// Reopen the notch after a screenshot when the pointer is still over it.
    var reopenNotch: Bool = true

    static let defaultPattern = "{kind} {date} at {time}"
    static let delayChoices = [0, 3, 10]
    static let recordingLimitChoices = [0, 30, 60, 300, 900]

    static let `default` = CaptureWidgetSettings()

    var gridSizeType: NookWidget.NookGridSizeType { .small }

    init() {}

    // Tolerant decoding: a missing or undecodable field keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.decodeSetting(.destination, into: &destination)
        c.decodeSetting(.filenamePattern, into: &filenamePattern)
        c.decodeSetting(.delaySeconds, into: &delaySeconds)
        c.decodeSetting(.imageFormat, into: &imageFormat)
        c.decodeSetting(.playSounds, into: &playSounds)
        c.decodeSetting(.windowShadow, into: &windowShadow)
        c.decodeSetting(.showClicks, into: &showClicks)
        c.decodeSetting(.recordingLimitSeconds, into: &recordingLimitSeconds)
        c.decodeSetting(.reopenNotch, into: &reopenNotch)
    }

    private enum CodingKeys: String, CodingKey {
        case destination, filenamePattern, delaySeconds, imageFormat, playSounds, windowShadow,
             showClicks, recordingLimitSeconds, reopenNotch
    }

    /// The file name (without extension) for a capture of `kind` taken at `date`.
    func fileName(kind: CaptureKind, date: Date = Date()) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH.mm.ss"
        var name = filenamePattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = Self.defaultPattern }
        name = name
            .replacingOccurrences(of: "{kind}", with: kind.isRecording ? "Screen Recording" : "Screenshot")
            .replacingOccurrences(of: "{date}", with: day.string(from: date))
            .replacingOccurrences(of: "{time}", with: time.string(from: date))
        // no path separators or colons (Finder shows ':' as '/'); no leading dot
        name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? "Capture" : name
    }
}

extension SettingKey {
    static let captureWidgetSettings = "captureWidgetSettings"
}

extension StoredKeys {
    static let captureWidgetSettings = Key<CaptureWidgetSettings>(SettingKey.captureWidgetSettings, default: .default)
}
