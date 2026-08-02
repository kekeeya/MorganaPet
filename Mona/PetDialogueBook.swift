//
//  PetDialogueBook.swift
//  Mona
//

import Foundation

/// One file's worth of lines, as stored in `Mona/Dialogue`.
struct PetDialogueFile: Codable {
    /// What this file is for. JSON has no comments, so this is where one goes.
    var note: String?
    var lines: [Entry]

    struct Entry: Codable {
        var message: String
        var expression: String
        var note: String?
    }
}

/// The occasions Mona has something to say. One file each: every file is small
/// enough to take in at a glance, and a new occasion is a new file rather than
/// another section to find inside a large one.
enum PetDialogueScenario: String, CaseIterable {
    case pokeCasual = "poke-casual"
    case pokePestered = "poke-pestered"
    case strokeHead = "stroke-head"
    case strokeBelly = "stroke-belly"
    case strokeFeet = "stroke-feet"
    case strokeTail = "stroke-tail"
    case quotaUnavailable = "quota-unavailable"
    case quotaExhausted = "quota-exhausted"
    case quotaPlenty = "quota-plenty"
    case quotaLow = "quota-low"
    case quotaStale = "quota-stale"
    case quotaExpired = "quota-expired"
    case nightEarly = "night-early"
    case nightLate = "night-late"
    case nightDeep = "night-deep"
    case hourPlain = "hour-plain"
    case hourMorning = "hour-morning"
    case hourNoon = "hour-noon"
    case hourEvening = "hour-evening"
    case hourNight = "hour-night"
    case statusCPU = "status-cpu"
    case statusCPUBusy = "status-cpu-busy"
    case statusMemory = "status-memory"
    case statusMemoryTight = "status-memory-tight"
    case statusStorage = "status-storage"
    case statusStorageFull = "status-storage-full"
    case statusBattery = "status-battery"
    case statusBatteryLow = "status-battery-low"
    case statusNetwork = "status-network"
    case statusNetworkOffline = "status-network-offline"
    case statusNetworkNoAddress = "status-network-no-address"
    case claudeUsageUnavailable = "claude-usage-unavailable"
    case claudeUsageStale = "claude-usage-stale"
    case claudeUsageFiveHour = "claude-usage-5h"
    case claudeUsageFiveHourTight = "claude-usage-5h-tight"
    case claudeUsageSevenDay = "claude-usage-7d"
    case claudeUsageSevenDayTight = "claude-usage-7d-tight"
}

extension PetDialogueScenario {
    /// Values this occasion can report, by the name they go by in braces.
    ///
    /// One list, read both by the code that fills lines in and by the checker
    /// that flags a `{typo}` nothing will ever replace. Kept together because the
    /// two drifting apart is exactly the failure that would go unnoticed: an
    /// unfilled placeholder shows up as literal braces in what he says.
    var placeholders: Set<String> {
        switch self {
        case .quotaExhausted:
            return ["window", "reset"]
        case .quotaPlenty, .quotaLow:
            return ["window", "used", "reset"]
        case .quotaStale:
            return ["age"]
        case .quotaExpired:
            return ["window"]
        case .hourPlain, .hourMorning, .hourNoon, .hourEvening, .hourNight:
            return ["hour"]
        case .statusCPU, .statusCPUBusy:
            return ["cpu", "user", "system", "idle"]
        case .statusMemory, .statusMemoryTight:
            return ["memory", "pressure", "app", "wired", "compressed", "free", "total"]
        case .statusStorage, .statusStorageFull:
            return ["storage", "used", "free", "total"]
        case .statusBattery, .statusBatteryLow:
            return ["battery", "source", "health", "cycles", "temperature"]
        case .statusNetwork:
            return ["interface", "ip", "upload", "download"]
        case .statusNetworkOffline:
            return []
        case .statusNetworkNoAddress:
            return ["interface", "upload", "download"]
        case .claudeUsageStale:
            return ["age"]
        case .claudeUsageFiveHour, .claudeUsageFiveHourTight,
             .claudeUsageSevenDay, .claudeUsageSevenDayTight:
            return ["used", "left", "resets"]
        default:
            return []
        }
    }
}

/// Everything Mona can say.
///
/// The files in `Mona/Dialogue` are the only copy — nothing is duplicated in
/// Swift, so editing a line is editing the line, and the change shows up in the
/// diff like any other.
final class PetDialogueBook {
    static let shared = PetDialogueBook()

    /// Problems found the last time the files were read. Empty is the only
    /// acceptable value; `Tools/VerifyDialogue.swift` checks it in the repo so a
    /// typo is caught before it ever ships.
    private(set) var issues: [String] = []

    private var pools: [PetDialogueScenario: [DialoguePage]] = [:]

    func pages(for scenario: PetDialogueScenario) -> [DialoguePage] {
        pools[scenario] ?? []
    }

    /// Reads every scenario. Returns whatever was wrong, in the order found.
    @discardableResult
    func load(from bundle: Bundle = .main) -> [String] {
        var found: [String] = []
        var loaded: [PetDialogueScenario: [DialoguePage]] = [:]

        for scenario in PetDialogueScenario.allCases {
            let name = scenario.rawValue
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                found.append("\(name).json 没有打包进来")
                loaded[scenario] = []
                continue
            }
            do {
                let file = try JSONDecoder().decode(
                    PetDialogueFile.self,
                    from: try Data(contentsOf: url)
                )
                if file.lines.isEmpty {
                    found.append("\(name).json 里一句台词都没有")
                }
                loaded[scenario] = file.lines.enumerated().map { index, entry in
                    guard let expression = PetExpression(rawValue: entry.expression) else {
                        found.append(
                            "\(name).json 第 \(index + 1) 句：表情「\(entry.expression)」不认识，"
                                + "暂时按 regular 显示"
                        )
                        return DialoguePage(message: entry.message, expression: .regular)
                    }
                    return DialoguePage(message: entry.message, expression: expression)
                }
            } catch {
                found.append("\(name).json 读不了：\(error.localizedDescription)")
                loaded[scenario] = []
            }
        }

        pools = loaded
        issues = found
        return found
    }
}

extension Array where Element == DialoguePage {
    /// Substitutes `{name}` placeholders. Used by the quota lines, which are the
    /// only ones that report a live value.
    func filling(_ values: [String: String]) -> [DialoguePage] {
        map { page in
            var message = page.message
            for (name, value) in values {
                message = message.replacingOccurrences(of: "{\(name)}", with: value)
            }
            return DialoguePage(message: message, expression: page.expression)
        }
    }
}
