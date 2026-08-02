//
//  PetTouchState.swift
//  Mona
//

import Foundation
import SwiftUI

/// Where on the sprite a stroke is landing.
enum PetTouchZone {
    case head
    case belly
    case feet
    case tail
    /// On him, but between the bands. Keeps a session alive without claiming a
    /// reaction of its own.
    case neutral
}

extension PetTouchZone {
    /// What he pulls while a hand is there, shown whether or not he also has
    /// something to say about it — the lines are on a cooldown, the face is not.
    var strokeExpression: PetExpression? {
        switch self {
        case .head:
            return .smile
        case .belly, .feet:
            return .angry
        case .tail:
            return .shocked
        case .neutral:
            return nil
        }
    }
}

/// Hand-tuned feel constants, gathered here so stroking can be adjusted in one
/// place.
enum PetTouchTuning {
    /// Bands as a fraction of the sprite frame's height, measured from the top.
    /// Read off the artwork: the head block holds a steady width down to about
    /// 0.48, the body narrows below it, and the feet start around 0.86. The head
    /// runs a little past where the drawing ends because people aim for it, and
    /// the gap before the belly band means a near-miss does nothing rather than
    /// guessing wrong.
    static let headBand: ClosedRange<Double> = 0...0.52
    static let bellyBand: ClosedRange<Double> = 0.62...0.86
    static let feetBand: ClosedRange<Double> = 0.88...1

    /// The tail hangs off to his left across the same rows as the belly, so it is
    /// the one part that cannot be told apart by height alone.
    static let tailBand: ClosedRange<Double> = 0.60...0.86
    static let tailColumns: ClosedRange<Double> = 0.10...0.32

    /// Horizontal travel that counts as one pass of a hand.
    static let strokeTravel: Double = 8

    /// More than this in a single sample is the pointer being warped rather than
    /// a hand moving.
    static let maxSampleTravel: Double = 150

    /// Direction changes needed inside `strokeWindow` before this reads as
    /// stroking rather than the cursor merely crossing over him.
    static let requiredReversals = 2
    static let strokeWindow: TimeInterval = 0.9

    /// The cursor has to have settled on him for this long before its movement
    /// counts. The sweep that carries the pointer onto him is travel, not a
    /// stroke, and it is far longer than anything a rubbing hand produces.
    static let entryGrace: TimeInterval = 0.2

    /// How much of the ground covered may end up as net progress across the
    /// window. A rubbing hand goes back and forth without getting anywhere, so
    /// its net travel is a small share of its path; a hand on its way somewhere
    /// spends nearly all of its path getting there. Two small corrections after
    /// arriving are what used to slip through, and this is what catches them.
    static let maxNetTravelShare: Double = 0.5

    /// Once stroking, it continues as long as the hand keeps covering ground this
    /// often. Kept separate from `strokeWindow` on purpose: an unhurried rub
    /// reverses less often than the starting window is wide, so reusing the start
    /// condition to stay latched would make a gentle stroke flicker in and out.
    static let strokeLapse: TimeInterval = 0.7

    /// How far he leans after the hand, in degrees.
    static let leanDegrees: Double = 4

    /// A remark while being handled, at most this often.
    static let remarkCooldown: TimeInterval = 22

    /// Sparkle-eyed payoff once the hand lifts.
    static let afterglow: TimeInterval = 0.7
}

/// How Mona is being handled, published from AppKit into the SwiftUI hierarchy.
/// The counterpart to `PetInteractionRegions`, which flows the other way.
@Observable
final class PetTouchState {
    /// Non-nil while a hand is stroking him.
    var strokedZone: PetTouchZone?

    /// Degrees he leans, following the hand.
    var strokeLean: Double = 0

    /// Whether he is on screen at all. Speaking up while hidden would burn the
    /// occasion on nobody.
    var isPetVisible = true
}

/// How long since the last input anywhere on the system — not just to Mona.
///
/// Needs no permission, unlike anything that would report *what* was typed.
enum PetSystemIdle {
    static func seconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: ~0) ?? .null
        )
    }
}

/// Turns a stream of cursor positions into "a hand is stroking him".
///
/// Deliberately hover-based. Pressing and rubbing is the same input as dragging
/// the window, so requiring that no button is held keeps the two gestures from
/// competing for the same motion — no need to guess intent from the path shape,
/// and no need to snap the window back after guessing wrong.
///
/// Pure logic, so the thresholds can be exercised with a synthetic stream rather
/// than by rubbing at the screen and squinting.
struct PetStrokeRecognizer {
    private(set) var zone: PetTouchZone?
    private(set) var lean: Double = 0

    /// One committed sweep of the hand: far enough to mean something, in a
    /// single direction.
    private struct Pass {
        let direction: Int
        let length: Double
        let at: TimeInterval
    }

    private var lastX: Double?
    private var travel: Double = 0
    private var direction = 0
    private var passes: [Pass] = []
    private var candidateZone: PetTouchZone?
    private var lastPassAt: TimeInterval?
    private var onPetSince: TimeInterval?

    /// Feeds one cursor sample. Pass `nil` for `sampleZone` when the cursor is
    /// not on the sprite at all.
    mutating func track(x: Double, zone sampleZone: PetTouchZone?, at time: TimeInterval) {
        guard let sampleZone else {
            reset()
            return
        }

        defer { lastX = x }

        if onPetSince == nil {
            onPetSince = time
        }

        // Whichever band the hand started on owns the session, so drifting
        // through the gap between bands does not reclassify it mid-stroke.
        if sampleZone != .neutral, candidateZone == nil || zone == nil {
            candidateZone = sampleZone
        }

        guard let lastX else { return }

        // The sweep that brought the cursor here is travel, not stroking.
        guard let onPetSince, time - onPetSince >= PetTouchTuning.entryGrace else {
            travel = 0
            return
        }

        let delta = x - lastX

        // A jump this large is the pointer being warped, not a hand. Counting it
        // would register a pass in each direction and latch on its own.
        guard abs(delta) <= PetTouchTuning.maxSampleTravel else {
            travel = 0
            return
        }

        if travel == 0 || (delta < 0) == (travel < 0) {
            travel += delta
        } else {
            travel = delta
        }

        var committedPass = false
        if abs(travel) >= PetTouchTuning.strokeTravel {
            let passDirection = travel < 0 ? -1 : 1
            passes.append(Pass(direction: passDirection, length: abs(travel), at: time))
            direction = passDirection
            travel = 0
            lastPassAt = time
            committedPass = true
        }

        evaluate(at: time, committedPass: committedPass)
    }

    /// Re-evaluates without a new sample, so a hand that simply stops moving is
    /// noticed rather than leaving him squinting forever.
    mutating func settle(at time: TimeInterval) {
        evaluate(at: time, committedPass: false)
    }

    mutating func reset() {
        lastX = nil
        travel = 0
        direction = 0
        passes.removeAll()
        candidateZone = nil
        lastPassAt = nil
        onPetSince = nil
        zone = nil
        lean = 0
    }

    /// Direction changes among the passes still inside the window.
    private var reversalCount: Int {
        zip(passes, passes.dropFirst()).count { $0.direction != $1.direction }
    }

    /// Ground covered, against ground gained. A rubbing hand covers a lot of the
    /// former and almost none of the latter.
    private var isWandering: Bool {
        let path = passes.reduce(0) { $0 + $1.length }
        let net = abs(passes.reduce(0) { $0 + Double($1.direction) * $1.length })
        return net <= path * PetTouchTuning.maxNetTravelShare
    }

    private mutating func evaluate(at time: TimeInterval, committedPass: Bool) {
        passes.removeAll { time - $0.at > PetTouchTuning.strokeWindow }

        guard let candidateZone, candidateZone != .neutral else {
            clearStroke()
            return
        }

        if zone == nil {
            // Only movement may start a stroke, never the mere passing of time.
            // The window slides, so a hand that arrived and then made two small
            // corrections eventually has its long approach expire out of view,
            // leaving behind two short opposed passes that look exactly like
            // rubbing. Requiring a fresh pass keeps that from ever being read.
            guard committedPass else { return }

            // Starting takes a burst of back-and-forth that goes nowhere.
            guard reversalCount >= PetTouchTuning.requiredReversals, isWandering else {
                return
            }
        } else {
            // Continuing only takes a hand that is still covering ground.
            guard let lastPassAt,
                  time - lastPassAt <= PetTouchTuning.strokeLapse
            else {
                clearStroke()
                return
            }
        }

        zone = candidateZone
        lean = Double(direction) * PetTouchTuning.leanDegrees
    }

    private mutating func clearStroke() {
        zone = nil
        lean = 0
    }
}

/// What he says about being stroked. The lines themselves live in editable
/// files; see `PetDialogueBook`.
enum PetStrokeDialogue {
    static func page(for zone: PetTouchZone, avoiding previous: String?) -> DialoguePage? {
        let scenario: PetDialogueScenario
        switch zone {
        case .head:
            scenario = .strokeHead
        case .belly:
            scenario = .strokeBelly
        case .feet:
            scenario = .strokeFeet
        case .tail:
            scenario = .strokeTail
        case .neutral:
            return nil
        }
        return PetDialogueBook.shared.pages(for: scenario).randomPage(avoiding: previous)
    }
}
