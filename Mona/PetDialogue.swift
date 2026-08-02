//
//  PetDialogue.swift
//  Mona
//

import Foundation

/// Who is speaking, and how strong a claim they have on the dialogue box.
///
/// One dialogue owns the box at a time. Making the claim explicit is what stops
/// priority from living in the order of `if` statements, where it could not be
/// read off the code or checked.
enum PetVoice: Int, Comparable {
    /// Said unprompted. Ranked below everything, because it is the only voice
    /// that interrupts rather than answers.
    case spontaneous = 5
    /// Murmured about being handled. Opportunistic: it waits for silence rather
    /// than talking over anything.
    case stroke = 10
    /// An idle remark when poked.
    case casual = 20
    /// Asked for from the menu, so these outrank anything he says unprompted.
    case quota = 60
    case machineStatus = 62
    /// He is worked up. Nothing else gets a word in until he is heard out.
    case pestered = 90

    static func < (lhs: PetVoice, rhs: PetVoice) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Minimum time on screen before an equal or lesser voice may replace it, and
    /// before a click may turn the page. Guards against a burst of clicks — the
    /// very thing that provokes half of these — wiping a line unread.
    var hold: TimeInterval {
        switch self {
        case .spontaneous, .stroke, .casual:
            return 0.6
        case .quota, .machineStatus:
            return 0.3
        case .pestered:
            return 0.35
        }
    }

    /// Whether this voice only speaks into silence. Petting is something he
    /// mentions if he has nothing else going on, not over what you are reading;
    /// an unprompted line has even less claim.
    var needsSilence: Bool {
        self == .stroke || self == .spontaneous
    }

    /// How long the line stays up on its own. Something you asked for waits
    /// until you are done with it; something he volunteered clears itself, since
    /// nobody should have to dismiss a remark they never asked for.
    var clearsAfter: TimeInterval {
        self == .spontaneous ? 12 : 60
    }
}

/// The three frames a talking expression cycles through.
struct DialogueMouthFrames {
    let open: String
    let halfOpen: String
    let closed: String
}

extension PetExpression {
    /// Artwork for this expression.
    ///
    /// Lives on the expression rather than in the view because it is also what
    /// tells `Tools/VerifyDialogue` which images a line needs. Held in two places
    /// it drifts, and the way it fails is silent: a missing frame does not crash,
    /// the mouth just stops moving.
    var mouthFrames: DialogueMouthFrames {
        // `smile` is the odd one out: its half-open frame was named before the
        // `-talk-half` convention settled.
        let halfOpen = self == .smile ? "smile-half" : "\(rawValue)-talk-half"
        return DialogueMouthFrames(
            open: "\(rawValue)-talk",
            halfOpen: halfOpen,
            closed: rawValue
        )
    }
}

extension Array where Element == DialoguePage {
    /// Never repeats the line that was just shown; the pools are small enough
    /// that hearing the same one twice in a row stands out.
    func randomPage(avoiding previous: String?) -> DialoguePage? {
        let candidates = filter { $0.message != previous }
        return candidates.randomElement() ?? first
    }
}
