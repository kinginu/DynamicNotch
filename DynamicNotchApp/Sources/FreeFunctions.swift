import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation
import EventKit
import SwiftUI
import AppKit


// Creates empty [Date: [EKEvent]] using swiftEmptyDictionarySingleton
// Gets Calendar.current
// For each event: gets startDate, computes Calendar.startOfDay(for:)
// Checks isMultiDay extension on EKEvent
// Gets endDate, checks isAllDay
// For all-day: uses Calendar.isDate(inSameDayAs:) to check if same day
// If not same day (or multi-day spanning): iterates from start → end day by day
// Day iteration uses Calendar.date(byAdding: .day, value: 1, to:)
// For non-all-day multi-day: checks timeIntervalSince < 86400.0
// For each day: appends event to dictionary[day] array
// After grouping: sorts each array by startDate via sort(by:)
// Returns the dictionary
func groupAndSortEventsByDateAndTime(_ events: [EKEvent]) -> [Date: [EKEvent]] {
    // Create empty dictionary
    var result: [Date: [EKEvent]] = [:]
    // Get current calendar
    let calendar = Calendar.current

    for event in events {
        // Get event startDate
        guard let startDate = event.startDate else { continue }

        // Compute startOfDay
        let startDay = calendar.startOfDay(for: startDate)

        // Get endDate
        guard let endDate = event.endDate else {
            // Single point event — add to start day
            result[startDay, default: []].append(event)
            continue
        }

        let endDay = calendar.startOfDay(for: endDate)

        // Check isAllDay
        if event.isAllDay {
            // Calendar.isDate(inSameDayAs:)
            if calendar.isDate(startDay, inSameDayAs: endDay) {
                // Same day — add once
                result[startDay, default: []].append(event)
            } else {
                // Multi-day all-day: iterate from startDay through endDay
                var current = startDay
                while current <= endDay {
                    result[current, default: []].append(event)
                    // Calendar.date(byAdding: .day, value: 1, to:)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                    current = next
                }
            }
        } else {
            // timeIntervalSince check against 86400.0 (seconds per day)
            let duration = endDate.timeIntervalSince(startDate)
            if duration < 86400.0 {
                // Less than one day — add to start day
                result[startDay, default: []].append(event)
            } else {
                // Multi-day non-all-day: iterate day by day
                var current = startDay
                while current <= endDay {
                    result[current, default: []].append(event)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                    current = next
                }
            }
        }
    }

    // Sort each day's array by startDate
    for date in result.keys {
        result[date]?.sort { a, b in
            let aDate = a.startDate ?? Date.distantPast
            let bDate = b.startDate ?? Date.distantPast
            return aDate < bDate
        }
    }

    return result
}


// Takes current CGRect, visible CGRect, chrome CGSize, expanded Bool
// When expanded: target size = (960, 625), when not: (704, 330)
// Computes min/mid/max fits for the settings window
// Accounts for chrome offset
// Returns fitted frame within visible bounds
func fittedNookSettingsFrame(
    current: CGRect,
    visible: CGRect,
    chrome: CGSize,
    expanded: Bool
) -> CGRect {
    // Frame dimensions based on expanded flag
    let frameWidth: CGFloat = expanded ? 960 : 704
    let frameHeight: CGFloat = expanded ? 625 : 330

    // Compute origin fit within visible bounds
    var newX = current.origin.x
    var newY = current.origin.y

    // Edge clamping
    if newX < visible.minX {
        newX = visible.minX
    }
    if newX + frameWidth > visible.maxX {
        newX = visible.maxX - frameWidth
    }
    if newY < visible.minY + chrome.height {
        newY = visible.minY + chrome.height
    }
    if newY + frameHeight > visible.maxY {
        newY = visible.maxY - frameHeight
    }

    return CGRect(x: newX, y: newY, width: frameWidth, height: frameHeight)
}


// Sends the file URLs among `items` with the AirDrop sharing service (logs and returns when
//   there are none).
func airDropItems(items: [URL]) {
    // Filter to file URLs only
    let fileURLs = items.filter { $0.isFileURL }

    // If no file URLs, nothing to share
    guard !fileURLs.isEmpty else {
        print("No file URLs to AirDrop")
        return
    }

    // Create NSSharingService for AirDrop
    // init(named:) is failable
    guard let sharingService = NSSharingService(
        named: NSSharingService.Name.sendViaAirDrop
    ) else { return }

    // Check canPerform
    if sharingService.canPerform(withItems: fileURLs as [Any]) {
        sharingService.perform(withItems: fileURLs as [Any])
    }
}


// Uses dictionary mapping service names to URL patterns
// First checks EKEvent.location for meeting URL patterns
// Then checks EKEvent.notes for meeting URL patterns
// Uses range(of:options:caseInsensitive)
// Detects Zoom, Google Meet, Microsoft Teams, etc.
func detectMeetings(in event: EKEvent?) -> Meeting? {
    guard let event = event else { return nil }

    // Domain string → VideoConferenceService mapping
    let servicePatterns: [(String, VideoConferenceService)] = [
        ("zoom.us", .zoom),
        ("meet.google.com", .googleMeet),
        ("teams.microsoft.com", .teams),
        ("webex.com", .webex),
        ("skype.com", .skype),
        ("gotomeeting.com", .gotoMeeting),
        ("discord.com", .discord),
    ]

    // Check location then notes then url
    var textToSearch = event.location ?? ""
    if let notes = event.notes { textToSearch += " " + notes }
    if let urlStr = event.url?.absoluteString { textToSearch += " " + urlStr }

    for (domain, service) in servicePatterns {
        if textToSearch.range(of: domain, options: .caseInsensitive) != nil {
            /* Extract meeting URL from the first non-nil field that is a valid URL */
            let candidates: [URL?] = [event.url, event.location.flatMap({ URL(string: $0) }), event.notes.flatMap({ URL(string: $0) })]
            if let url = candidates.compactMap({ $0 }).first {
                return Meeting(url: url, service: service)
            }
        }
    }

    return nil
}


// Called from CalendarWidgetView
// Generates sequential dates: middleDate - beforeCount days ... middleDate + afterCount days
// Uses Calendar.date(byAdding: .day, value: n, to: middleDate)
func getRangeOfDays(beforeCount: Int, afterCount: Int, middleDate: Date) -> [Date] {
    let calendar = Calendar.current
    var dates: [Date] = []

    // Generate dates from (middleDate - beforeCount) through (middleDate + afterCount)
    for offset in -beforeCount...afterCount {
        if let date = calendar.date(byAdding: .day, value: offset, to: middleDate) {
            dates.append(date)
        }
    }

    return dates
}


// Checks URL pathExtension against known image extensions
// Known extensions: png, jpg, jpeg, gif, bmp, tiff, heic
// If matched → NSImage(contentsOf:) → SwiftUI.Image
// Returns nil if not an image extension
func loadImgFromURL(_ url: URL) -> Image? {
    // Check image extensions
    let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic"]

    let ext = url.pathExtension.lowercased()
    guard imageExtensions.contains(ext) else {
        return nil
    }

    // Load NSImage from URL
    guard let nsImage = NSImage(contentsOf: url) else {
        return nil
    }

    // Convert to SwiftUI Image
    return Image(nsImage: nsImage)
}


// If URL provided → use that. Otherwise use FileManager.default.temporaryDirectory
// Appends "DynamicNotchTemp" component to temp dir
// Checks fileExists → removeItem
// Also lists directory contents, matches with regex, removes matched files
func cleanupTemporaryDirectory(_ url: URL? = nil) {
    let fileManager = FileManager.default

    // Use provided URL or temp directory
    let baseURL: URL
    if let url = url {
        baseURL = url
    } else {
        baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("DynamicNotchTemp")
    }

    // Remove the main temp directory if it exists
    if fileManager.fileExists(atPath: baseURL.path) {
        try? fileManager.removeItem(at: baseURL)
    }

    // Also iterate contents and remove matching files (regex pattern)
    if let contents = try? fileManager.contentsOfDirectory(
        at: baseURL,
        includingPropertiesForKeys: nil,
        options: []
    ) {
        for fileURL in contents {
            /* Remove temp files matching DynamicNotch* pattern */
            let name = fileURL.lastPathComponent
            if name.hasPrefix("DynamicNotch") {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}


// Uses DispatchQueue.main.asyncAfter(deadline: .now() + CGFloat, qos: .unspecified)
// Executes callback block
func doAfter(_ delay: CGFloat, callback: @escaping () -> Void) {
    // DispatchQueue.main.asyncAfter
    DispatchQueue.main.asyncAfter(
        deadline: .now() + Double(delay),
        qos: .unspecified,
        flags: [],
        execute: callback
    )
}
