// TimerEntry — one Timer-widget timer (label, duration, remaining time, state), owned and mutated
// by NookTimersStore on the main actor; views observe it directly.
import Foundation
import Observation

@Observable
final class TimerEntry: Codable, Identifiable {

    enum State: String, Codable, Equatable, Hashable, CaseIterable {
        case idle
        case running
        case paused
        case expired
        case cancelled
    }

    enum CodingKeys: String, CodingKey {
        case id, label, totalSeconds, remainingSeconds, state, startedAt, expiresAt
    }

    let id: UUID
    var label: String = ""
    var totalSeconds: Int = 0
    var remainingSeconds: Int = 0
    var state: State = .idle
    var startedAt: Date? = nil
    var expiresAt: Date? = nil

    init(id: UUID = UUID(), label: String, totalSeconds: Int) {
        self.id = id
        self.label = label
        self.totalSeconds = totalSeconds
        self.remainingSeconds = totalSeconds
    }

    // MARK: - Codable

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        totalSeconds = try container.decode(Int.self, forKey: .totalSeconds)
        remainingSeconds = try container.decode(Int.self, forKey: .remainingSeconds)
        state = try container.decode(State.self, forKey: .state)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(totalSeconds, forKey: .totalSeconds)
        try container.encode(remainingSeconds, forKey: .remainingSeconds)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }
}

// MARK: - Presentation helpers

// State meanings used by NookTimersStore:
//   .running   counting down (`expiresAt` set);
//   .idle      paused (`pause(_:)` sets `.idle` and clears `expiresAt`; `remainingSeconds` is kept);
//   .cancelled ended (the tick sets `.cancelled` when a timer reaches 0); `.expired` is treated
//              the same. `.paused` is not used.
extension TimerEntry {
    var isRunning: Bool { state == .running }
    var isPaused: Bool { state == .idle }
    var hasEnded: Bool { state == .cancelled || state == .expired }

    /// Seconds left, precise while running (for rings), else the stored value.
    func remaining(at date: Date = Date()) -> TimeInterval {
        if isRunning, let expiresAt { return max(0, expiresAt.timeIntervalSince(date)) }
        return hasEnded ? 0 : TimeInterval(max(0, remainingSeconds))
    }

    /// Fraction of the duration still left (1 → 0), like the Dynamic Island ring.
    func progress(at date: Date = Date()) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, remaining(at: date) / Double(totalSeconds)))
    }

    /// The label, or "Timer" when it has none (iOS shows "Timer" for unlabelled timers).
    var displayLabel: String { label.isEmpty ? String(localized: "Timer") : label }
}
