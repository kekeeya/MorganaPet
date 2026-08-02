//
//  PetSleep.swift
//  Mona
//

import Foundation

enum PetSleepTuning {
    /// The small hours, when a cat left alone would have dozed off. Outside
    /// these he stays up however long he is ignored — being ignored at three in
    /// the afternoon is not the same thing.
    static let hours = [0, 1, 2, 3, 4, 5]

    /// Left alone this long and he drops off.
    static let after: TimeInterval = 10 * 60
}

/// How long the lid spends at each stage of an ordinary blink.
///
/// Shared with nodding off, because that is the same blink with the shut frame
/// swapped for the sleeping face. Kept in one place so tuning the blink cannot
/// leave the one that reads well and the one that does not on different rhythms.
enum PetBlinkTiming {
    static let lid: TimeInterval = 0.065
    static let shut: TimeInterval = 0.075
}

/// One frame of nodding off: hold this image for this long.
struct PetSleepBeat {
    let imageName: String
    let duration: TimeInterval
}

/// Whether Mona has fallen asleep.
///
/// Keyed to being left alone by *you*, not to the machine going idle: he is
/// waiting on your attention, and someone typing away in another window all
/// night is exactly the case where he should be curled up asleep.
enum PetSleep {
    /// Nodding off rather than switching off. His eyes droop, he catches himself
    /// and opens them again, droops once more, goes under — and gives one last
    /// flicker before settling.
    ///
    /// The steady sleeping face is not in the list: it is what he falls through
    /// to once the beats run out, so the handover needs no frame of its own.
    /// How long his eyes stay open between the blink and the droop that follows
    /// it. The only beat here not taken from the blink itself.
    static let beforeDrooping: TimeInterval = 0.18

    /// One ordinary blink, and then the lids come down again and stay down.
    ///
    /// Every eyelid beat is the blink's own timing, so the first half of this is
    /// indistinguishable from him simply blinking — which is the point: you only
    /// realise it was him nodding off when the second one does not open.
    static let dozeOff: [PetSleepBeat] = [
        PetSleepBeat(imageName: "blink-half", duration: PetBlinkTiming.lid),
        PetSleepBeat(imageName: "blink", duration: PetBlinkTiming.shut),
        PetSleepBeat(imageName: "blink-half", duration: PetBlinkTiming.lid),
        PetSleepBeat(imageName: PetExpression.regular.rawValue, duration: beforeDrooping),
        PetSleepBeat(imageName: "blink-half", duration: PetBlinkTiming.lid)
    ]

    static func isAsleep(
        at time: Date,
        sinceTouched: TimeInterval,
        calendar: Calendar = .current
    ) -> Bool {
        guard PetSleepTuning.hours.contains(calendar.component(.hour, from: time)) else {
            return false
        }
        return sinceTouched >= PetSleepTuning.after
    }
}
