import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// Raw-representable string enum for meeting platforms
enum VideoConferenceService: String, Equatable, Hashable, CaseIterable {
    case zoom           // zoom.us / zoom.com
    case teams          // teams.microsoft.com
    case googleMeet     // meet.google.com
    case webex          // webex.com
    case skype          // skype.com
    case gotoMeeting    // gotomeeting.com
    case discord        // discord.com

    // display name used by CalendarEventView.meetingButton
    var localizedName: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .googleMeet: return "Google Meet"
        case .webex: return "Webex"
        case .skype: return "Skype"
        case .gotoMeeting: return "GoTo Meeting"
        case .discord: return "Discord"
        }
    }

    // SF Symbol used by CalendarEventView.meetingButton
    var systemImageName: String { "video.fill" }
}
