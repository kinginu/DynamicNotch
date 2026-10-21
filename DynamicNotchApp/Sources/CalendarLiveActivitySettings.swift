import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
import Foundation

// MARK: - CalendarLiveActivitySettings

// Settings controlling calendar live activity widget appearance and behavior
struct CalendarLiveActivitySettings: Preferences, Decodable, Encodable, Equatable, Hashable {

    // MARK: - Stored properties

    // General enable/disable
    var isEnabled: Bool = true

    // Appearance mode
    var appearanceMode: AppearanceMode = .constant

    // Days to look ahead
    var daysAhead: Int = 7

    // Maximum event count to display
    var maxEventCount: Int = 5

    // Show all-day events
    var showAllDayEvents: Bool = true

    // minutes before an event's start at which the closed-notch activity appears
    var minutesBefore: Int = 10

    // Encode each property

    // Hash all properties

    // MARK: - CodingKeys


    // MARK: - AppearanceMode

    // raw String enum so Codable is synthesized (encoded as "constant"/"periodic")
    enum AppearanceMode: String, Codable, Equatable, Hashable, CaseIterable {
        case constant
        case periodic
    }
}

// tolerant decoding (keys added later may be missing in stored values)
extension CalendarLiveActivitySettings {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? isEnabled
        appearanceMode = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? appearanceMode
        daysAhead = try c.decodeIfPresent(Int.self, forKey: .daysAhead) ?? daysAhead
        maxEventCount = try c.decodeIfPresent(Int.self, forKey: .maxEventCount) ?? maxEventCount
        showAllDayEvents = try c.decodeIfPresent(Bool.self, forKey: .showAllDayEvents) ?? showAllDayEvents
        minutesBefore = try c.decodeIfPresent(Int.self, forKey: .minutesBefore) ?? minutesBefore
    }
}
