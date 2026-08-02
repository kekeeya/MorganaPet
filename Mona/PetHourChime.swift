//
//  PetHourChime.swift
//  Mona
//

import Foundation

enum PetHourTuning {
    /// How long after the hour he may still call it out. Short, because the
    /// point of the line is the number in it: announcing three o'clock at
    /// twenty past would be worse than saying nothing.
    static let window: TimeInterval = 5 * 60

    /// A gap in typing worth speaking into, as elsewhere.
    static let lull: TimeInterval = 3
    static let away: TimeInterval = 5 * 60
    static let afterInteraction: TimeInterval = 30
}

/// Calls out the hour, on the hour.
///
/// Unlike the bedtime nagging this is meant to be regular — a clock striking,
/// not a remark — so there is no dice roll. What it shares is the reluctance to
/// interrupt: it waits for a pause, says nothing to an empty desk, and gives up
/// once the hour it would be announcing has stopped being true.
struct PetHourChime {
    /// The hour mark already dealt with, announced or given up on.
    private var handledHour: Date?
    private var isPending = false

    init(lastChimedHour: Date? = nil) {
        handledHour = lastChimedHour
    }

    /// The hour just announced, so a relaunch does not repeat it.
    private(set) var chimedHour: Date?

    /// Deliberately not subject to the gap that keeps unprompted lines apart:
    /// the hour is the one thing here that has to be said when it is true, so it
    /// takes precedence and the nagging is what waits.
    ///
    /// Decides only — `confirm` is what marks the hour used, so an hour that was
    /// decided on but could not be shown is tried again rather than lost.
    ///
    /// - Returns: the lines to draw from and the hour to fill in, or nil.
    mutating func consider(
        now: Date,
        userIdle: TimeInterval,
        sinceInteraction: TimeInterval,
        calendar: Calendar = .current
    ) -> (scenario: PetDialogueScenario, hour: Int)? {
        let hour = calendar.component(.hour, from: now)
        guard let hourMark = calendar.date(
            bySettingHour: hour, minute: 0, second: 0, of: now
        ) else {
            return nil
        }

        if handledHour != hourMark {
            handledHour = hourMark
            // Meeting an hour already long past — the app having started
            // mid-hour — counts as dealt with, not as owing a late chime.
            isPending = now.timeIntervalSince(hourMark) <= PetHourTuning.window
        }

        guard isPending,
              now.timeIntervalSince(hourMark) <= PetHourTuning.window,
              userIdle < PetHourTuning.away,
              sinceInteraction >= PetHourTuning.afterInteraction,
              userIdle >= PetHourTuning.lull
        else {
            // Once the window has passed the hour is written off either way.
            if isPending, now.timeIntervalSince(hourMark) > PetHourTuning.window {
                isPending = false
            }
            return nil
        }

        return (Self.scenario(forHour: hour), hour)
    }

    /// Marks the hour as said. Only called once the line is actually on screen.
    mutating func confirm() {
        isPending = false
        chimedHour = handledHour
    }

    /// Which greeting the hour calls for. Every hour of the day lands in exactly
    /// one of these.
    static func scenario(forHour hour: Int) -> PetDialogueScenario {
        switch hour {
        case 22, 23, 0, 1, 2, 3, 4, 5:
            return .hourNight
        case 6...11:
            return .hourMorning
        case 12...14:
            return .hourNoon
        case 18...21:
            return .hourEvening
        default:
            return .hourPlain
        }
    }

    /// How the hour reads in the line. Midnight is written out: "现在0点了"
    /// looks like a placeholder that failed to fill.
    static func spoken(hour: Int) -> String {
        hour == 0 ? "零" : "\(hour)"
    }
}
