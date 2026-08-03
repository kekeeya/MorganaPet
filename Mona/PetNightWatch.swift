//
//  PetNightWatch.swift
//  Mona
//

import Foundation

enum PetNightTuning {
    /// Hours he keeps watch over. Wraps past midnight.
    static let hours = [22, 23, 0, 1, 2, 3, 4]

    /// He rolls once per slot rather than speaking on a schedule, so the nagging
    /// does not tick like a clock. Half an hour is also long enough that two
    /// lines can never land close together, which saves needing a rule for it.
    static let slot: TimeInterval = 30 * 60

    /// Odds of speaking up in a given slot, by how late it is. The rate carries
    /// as much character as the lines do: a passing mention before midnight,
    /// genuinely insistent after it, and quieter again by three, by which point
    /// he has largely given up on you.
    static func chance(forHour hour: Int) -> Double {
        switch hour {
        case 22, 23:
            return 0.25
        case 0, 1, 2:
            return 0.45
        default:
            return 0.30
        }
    }

    /// Shortest gap between two lines. The slot length used to guarantee this on
    /// its own, until drawing a moment inside the slot made a line at the end of
    /// one and a line at the start of the next land minutes apart.
    static let minimumGap: TimeInterval = 20 * 60

    /// How far into a slot a line may be due. Stops short of the end so there is
    /// still room to wait for a pause.
    static let latestInSlot: TimeInterval = slot - 3 * 60

    /// A gap in typing this long counts as a pause worth speaking into. The same
    /// line lands as nagging mid-keystroke and as company when you look up.
    ///
    /// Nothing overrides this: with a fresh slot only half an hour away, waiting
    /// for a pause costs almost nothing, and a person typing goes this long
    /// without a keystroke many times an hour anyway.
    static let lull: TimeInterval = 3

    /// Idle for this long and the desk is empty; nagging it helps nobody.
    static let away: TimeInterval = 5 * 60

    /// Poked or stroked this recently and he stays quiet; he has just had his
    /// turn.
    static let afterInteraction: TimeInterval = 30
}

/// Decides when Mona should tell you to go to bed.
///
/// Pure, with the clock, the idle reading and the dice all passed in, so a whole
/// night can be played through in a test. Every guard here is invisible until it
/// is wrong, and being wrong means either nagging someone mid-keystroke or never
/// nagging at all — neither shows up in a quick try.
struct PetNightWatch {
    /// The slot whose roll has already been made.
    private var rolledSlot: Date?
    /// When in the slot a winning roll is due, if one is still owed. Drawn
    /// rather than fixed at the slot boundary: rolling for whether he speaks but
    /// always speaking on the half hour would leave the timing every bit as much
    /// a clock as before.
    private var dueAt: Date?
    /// The slot he last spoke in. Carried across launches so restarting mid-slot
    /// cannot buy that slot a second roll.
    ///
    /// How recently he last said *anything* unprompted is a separate matter and
    /// is passed in: the hourly chime speaks too, and the two have to keep out of
    /// each other's way.
    private(set) var spokenSlot: Date?

    init(spokenSlot: Date? = nil) {
        self.spokenSlot = spokenSlot
    }

    /// - Parameters:
    ///   - userIdle: seconds since the last input anywhere on the system.
    ///   - sinceInteraction: seconds since Mona was last poked or stroked.
    ///   - random: a draw from `0..<1`, injected so a night replays identically.
    /// Decides only — `confirm` is what spends the slot, so a line that was
    /// decided on but could not be shown is tried again rather than lost.
    ///
    /// - Returns: the lines to draw from, or nil to stay quiet.
    mutating func consider(
        now: Date,
        userIdle: TimeInterval,
        sinceInteraction: TimeInterval,
        sinceSpontaneous: TimeInterval,
        calendar: Calendar = .current,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> PetDialogueScenario? {
        let hour = calendar.component(.hour, from: now)
        guard PetNightTuning.hours.contains(hour) else {
            rolledSlot = nil
            dueAt = nil
            return nil
        }

        guard let slotStart = Self.slotStart(of: now, calendar: calendar) else { return nil }

        if rolledSlot != slotStart {
            rolledSlot = slotStart
            // A slot he has already spoken in gets no second roll, however the
            // app was restarted in the meantime.
            let wins = slotStart != spokenSlot
                && random() < PetNightTuning.chance(forHour: hour)
            dueAt = wins
                ? slotStart.addingTimeInterval(random() * PetNightTuning.latestInSlot)
                : nil
        }

        guard let dueAt,
              now >= dueAt,
              sinceSpontaneous >= PetNightTuning.minimumGap,
              userIdle < PetNightTuning.away,
              sinceInteraction >= PetNightTuning.afterInteraction,
              userIdle >= PetNightTuning.lull
        else {
            return nil
        }

        return Self.scenario(forHour: hour)
    }

    /// Marks the slot as spent. Only called once the line is actually on screen.
    mutating func confirm() {
        dueAt = nil
        spokenSlot = rolledSlot
    }

    static func slotStart(of time: Date, calendar: Calendar = .current) -> Date? {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }

        let slotMinutes = Int(PetNightTuning.slot / 60)
        return calendar.date(
            bySettingHour: hour,
            minute: minute / slotMinutes * slotMinutes,
            second: 0,
            of: time
        )
    }

    /// He works through the night in three tempers: still reasonable, then
    /// insistent, then resigned.
    static func scenario(forHour hour: Int) -> PetDialogueScenario {
        switch hour {
        case 22, 23:
            return .nightEarly
        case 0, 1, 2:
            return .nightLate
        default:
            return .nightDeep
        }
    }
}

/// Whether he is allowed to speak up on his own.
///
/// Anything that interrupts needs an obvious way to stop it, so the switch is a
/// checkbox in the settings window rather than something buried in a file.
enum PetQuietHours {
    /// Not private: the settings window binds to it directly, so the checkbox
    /// and this are one value rather than two copies to keep in step.
    static let disabledKey = "MonaSpontaneousDisabled"
    private static let nightSlotKey = "MonaNightSpokenSlot"
    private static let lastSpontaneousKey = "MonaLastSpontaneousAt"
    private static let chimedHourKey = "MonaLastChimedHour"

    static var isDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: disabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: disabledKey) }
    }

    /// Remembered so a relaunch does not re-roll a slot already used.
    static var nightSpokenSlot: Date? {
        get { UserDefaults.standard.object(forKey: nightSlotKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: nightSlotKey) }
    }

    /// Shared by the bedtime nagging and the hourly chime, so the two cannot
    /// land on top of one another.
    static var lastSpontaneousAt: Date? {
        get { UserDefaults.standard.object(forKey: lastSpontaneousKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSpontaneousKey) }
    }

    static var lastChimedHour: Date? {
        get { UserDefaults.standard.object(forKey: chimedHourKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: chimedHourKey) }
    }

}
