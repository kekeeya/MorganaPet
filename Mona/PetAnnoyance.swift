//
//  PetAnnoyance.swift
//  Mona
//

import Foundation

/// Hand-tuned feel constants, gathered here so the escalation can be adjusted in
/// one place.
enum PetAnnoyanceTuning {
    /// How much a single poke adds to the running level.
    static let pokeGain: Double = 0.22

    /// How fast the level drains, per second. This is what keeps ordinary
    /// page-turning from reading as harassment: poking at a conversational pace
    /// drains faster than it accumulates, so no special-casing of "was that
    /// click advancing a dialogue?" is needed.
    static let decayPerSecond: Double = 0.35

    static let irritatedThreshold: Double = 0.5
    static let furiousThreshold: Double = 0.85

    /// He stays annoyed after blowing up, but will not blow up again this soon —
    /// otherwise a long spam run chains angry dialogues back to back.
    static let furiousCooldown: TimeInterval = 6

    /// Odds that an unhurried poke earns a remark rather than just a shrug.
    static let casualChance: Double = 0.3

    // How long a line is owed on screen now belongs to `PetVoice.hold`, so every
    // kind of line answers the question the same way.
}

/// Tracks how much Mona is being pestered.
///
/// The level decays continuously in principle, but is only ever read when a poke
/// arrives, so this needs no timer of its own. Pure logic, so the escalation
/// curve can be checked against a synthetic click stream rather than by
/// hammering the sprite and guessing.
struct PetAnnoyance {
    enum Reaction {
        case tolerated
        case irritated
        case furious
    }

    private var storedLevel: Double = 0
    private var updatedAt: Date?
    private var lastFuriousAt: Date?

    func level(at time: Date) -> Double {
        guard let updatedAt else { return 0 }

        let elapsed = max(0, time.timeIntervalSince(updatedAt))
        return max(0, storedLevel - PetAnnoyanceTuning.decayPerSecond * elapsed)
    }

    mutating func registerPoke(at time: Date) -> Reaction {
        storedLevel = min(1, level(at: time) + PetAnnoyanceTuning.pokeGain)
        updatedAt = time

        if storedLevel >= PetAnnoyanceTuning.furiousThreshold, hasCooledDown(at: time) {
            lastFuriousAt = time
            return .furious
        }
        if storedLevel >= PetAnnoyanceTuning.irritatedThreshold {
            return .irritated
        }
        return .tolerated
    }

    /// Drops him straight back to calm. Hearing the crescendo out is what
    /// settles him, so finishing it counts for more than waiting out the decay.
    mutating func reset() {
        storedLevel = 0
        updatedAt = nil
        lastFuriousAt = nil
    }

    private func hasCooledDown(at time: Date) -> Bool {
        guard let lastFuriousAt else { return true }
        return time.timeIntervalSince(lastFuriousAt) >= PetAnnoyanceTuning.furiousCooldown
    }
}

/// One step of a shake: hold this angle for this long. Same shape as the mouth
/// animation's beats, and driven by the same sequence-guarded runner.
struct PetShakeBeat {
    let degrees: Double
    let duration: TimeInterval
}

extension PetAnnoyance.Reaction {
    /// Whether this reaction belongs to a worked-up run rather than him taking a
    /// poke in stride.
    ///
    /// Deliberately read off the reaction rather than off the annoyance level:
    /// the level dips back under the threshold between two rapid pokes even
    /// while he is plainly still agitated, so testing it directly would read
    /// every poke as a fresh bout.
    var isAgitated: Bool {
        self != .tolerated
    }

    /// Rotation only, about the sprite's centre — the same transform the existing
    /// poke uses, so the artwork never looks bent.
    ///
    /// The runner returns to zero once the beats run out, so none of these need a
    /// trailing rest.
    var shakeBeats: [PetShakeBeat] {
        switch self {
        case .tolerated:
            return [PetShakeBeat(degrees: -5, duration: 0.35)]
        case .irritated:
            return [
                PetShakeBeat(degrees: -8, duration: 0.12),
                PetShakeBeat(degrees: 6, duration: 0.12),
                PetShakeBeat(degrees: -4, duration: 0.13)
            ]
        case .furious:
            return [
                PetShakeBeat(degrees: -6, duration: 0.11),
                PetShakeBeat(degrees: 6, duration: 0.11),
                PetShakeBeat(degrees: -6, duration: 0.11),
                PetShakeBeat(degrees: 6, duration: 0.11),
                PetShakeBeat(degrees: -3, duration: 0.12)
            ]
        }
    }
}

/// What Mona says when he is prodded. The lines themselves live in editable
/// files; see `PetDialogueBook`.
enum PetPokeDialogue {
    static func casualPage(avoiding previous: String?) -> DialoguePage? {
        PetDialogueBook.shared.pages(for: .pokeCasual).randomPage(avoiding: previous)
    }

    /// The whole crescendo as one multi-page dialogue. Presenting it in one go
    /// is what lets it advance from the dialogue box rather than from poking, so
    /// a burst of clicks cannot skip past the lines faster than they read.
    static var pesteredPages: [DialoguePage] {
        PetDialogueBook.shared.pages(for: .pokePestered)
    }
}
