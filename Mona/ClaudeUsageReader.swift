//
//  ClaudeUsageReader.swift
//  Mona
//

import Foundation

/// What Claude Code knows about your subscription's two usage windows.
///
/// There is no API to ask for this — not on a personal plan. Claude Code fetches
/// it and holds it in memory, and the one place it hands it out is the status
/// line: whatever command you configure there is fed the session's full state on
/// stdin, `rate_limits` included. So the arrangement is to have that command
/// keep a copy on disk, and read the copy.
///
/// Which means the file is only as fresh as the last time Claude Code ran. That
/// is not a flaw to paper over — a stale figure reported as current is worse than
/// no figure, so the age travels with the reading and he says it out loud.
enum ClaudeUsageReader {
    /// Beyond this he stops calling the window comfortable.
    static let tightPercent: Double = 80

    /// Past this the reading is old enough to be worth mentioning. Claude Code
    /// rewrites the file every few hundred milliseconds while a session is live,
    /// so anything this old means it has not been running.
    static let staleAfter: TimeInterval = 10 * 60

    static func latestDialogue(now: Date = Date()) -> [DialoguePage] {
        let book = PetDialogueBook.shared
        guard let reading = latestReading() else {
            return book.pages(for: .claudeUsageUnavailable)
        }

        var pages: [DialoguePage] = []

        let age = now.timeIntervalSince(reading.takenAt)
        if age >= staleAfter {
            pages += book.pages(for: .claudeUsageStale)
                .filling(["age": phrase(forAge: age)])
        }

        if let window = reading.fiveHour {
            pages += windowPages(window, in: book,
                                 fresh: .claudeUsageFiveHour, tight: .claudeUsageFiveHourTight)
        }
        if let window = reading.sevenDay {
            pages += windowPages(window, in: book,
                                 fresh: .claudeUsageSevenDay, tight: .claudeUsageSevenDayTight)
        }

        // The file existed but carried neither window — same as having nothing.
        return pages.isEmpty ? book.pages(for: .claudeUsageUnavailable) : pages
    }

    private static func windowPages(
        _ window: Window,
        in book: PetDialogueBook,
        fresh: PetDialogueScenario,
        tight: PetDialogueScenario
    ) -> [DialoguePage] {
        let used = min(max(window.usedPercent, 0), 100)
        return book.pages(for: used >= tightPercent ? tight : fresh)
            .filling([
                "used": used.formatted(.number.precision(.fractionLength(0...1))),
                "left": (100 - used).formatted(.number.precision(.fractionLength(0...1))),
                "resets": phrase(untilReset: window.resetsAt)
            ])
    }

    // MARK: - Reading the file

    /// Wherever the status line was told to write. The default matches what the
    /// README tells you to configure; the override exists because that command is
    /// yours, and you may have pointed it somewhere else.
    static var statusLineURL: URL {
        let configured = PetPreferences.claudeStatusLine
        if !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/statusline.json", isDirectory: false)
    }

    /// The `statusLine` entry to paste into `~/.claude/settings.json`.
    ///
    /// Generated against the configured path rather than quoted from the README,
    /// so someone who moved the file is told to write to where Mona is actually
    /// looking. The command string is escaped by the JSON encoder — hand-escaping
    /// a shell command that already contains quotes, backslashes and a jq program
    /// is how a snippet ends up subtly wrong and unpasteable.
    static var statusLineSnippet: String {
        // `$HOME` when the file sits inside the home directory, so the line you
        // paste into a config you might share carries no username. A path chosen
        // elsewhere is written out in full, since there is nothing to abbreviate.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let full = statusLineURL.path
        let target = full.hasPrefix(home + "/")
            ? "$HOME" + full.dropFirst(home.count)
            : full

        let command = "tee \"\(target)\" | jq -r 'if .rate_limits then "
            + "\"5h \\(.rate_limits.five_hour.used_percentage // 0 | floor)% "
            + "· 7d \\(.rate_limits.seven_day.used_percentage // 0 | floor)%\" "
            + "else \"\" end' 2>/dev/null"

        let encoded = (try? JSONSerialization.data(withJSONObject: [command], options: [.withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let quoted = encoded.dropFirst().dropLast()   // 去掉 JSONSerialization 加的 [ ]

        return """
        "statusLine": {
          "type": "command",
          "command": \(quoted)
        }
        """
    }

    /// Whether `~/.claude/settings.json` already carries a status line pointing at
    /// the file this reader watches.
    ///
    /// Three answers rather than two, because `statusLine` is a single global
    /// slot: it can be unset, it can be set to something else entirely — another
    /// monitoring tool, most likely — or it can be ours. Reporting the middle case
    /// as "not configured" would send you to paste over someone else's setup.
    enum SettingsState {
        /// Carries where it actually writes, read back out of the file rather
        /// than assumed — the whole point of the tick is that it is evidence.
        case configured(destination: String)
        /// Carries what is there instead, so "something else" is not left as a
        /// mystery you have to go open the file to identify.
        case takenBySomethingElse(command: String)
        case missing

        var isConfigured: Bool {
            if case .configured = self { return true }
            return false
        }
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json", isDirectory: false)
    }

    static func settingsState() -> SettingsState {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let line = root["statusLine"] as? [String: Any],
            let command = line["command"] as? String
        else {
            return .missing
        }

        // The snippet we hand out writes a literal path, but a hand-written one
        // may well use $HOME — the same destination spelled differently.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded = command
            .replacingOccurrences(of: "$HOME", with: home)
            .replacingOccurrences(of: "${HOME}", with: home)
            .replacingOccurrences(of: "~/", with: home + "/")

        guard expanded.contains(statusLineURL.path) else {
            return .takenBySomethingElse(command: summarise(command))
        }
        return .configured(destination: abbreviate(destination(in: expanded) ?? statusLineURL.path))
    }

    /// The path the configured command writes to, taken from its `tee`.
    private static func destination(in command: String) -> String? {
        guard let range = command.range(
            of: #"tee\s+"([^"]+)""#, options: .regularExpression
        ) else {
            return nil
        }
        let matched = String(command[range])
        guard let quoted = matched.range(of: #""([^"]+)""#, options: .regularExpression) else {
            return nil
        }
        return String(matched[quoted]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// `~/…` rather than the full path: shorter to read, and no username on
    /// screen for anyone taking a screenshot.
    private static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// Enough of the other command to recognise it by, without spilling a jq
    /// program across the settings window.
    private static func summarise(_ command: String) -> String {
        let flat = command.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > 48 ? String(flat.prefix(48)) + "…" : flat
    }

    /// Distinguishes the three ways this comes up empty: no file at all (the
    /// status line was never configured), a file without `rate_limits` (it is
    /// configured but the session has not produced one yet, or the plan has no
    /// windows), and a reading that is simply old.
    static func probe(now: Date = Date()) -> (ok: Bool, detail: String) {
        let url = statusLineURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (false, "文件不存在 —— 还没配置 status line")
        }
        guard let reading = latestReading() else {
            return (false, "文件在，但没有 rate_limits（Pro/Max 才有）")
        }
        let age = now.timeIntervalSince(reading.takenAt)
        return (true, "已找到额度信息，\(duration(age))前。")
    }

    private static func latestReading() -> Reading? {
        let url = statusLineURL
        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let limits = root["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        // The file's own timestamp is the capture time — the status line rewrites
        // it on every update, so there is nothing to embed in the JSON.
        let takenAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast

        return Reading(
            takenAt: takenAt,
            fiveHour: window(from: limits["five_hour"]),
            sevenDay: window(from: limits["seven_day"])
        )
    }

    /// Either window may be absent on its own, so neither is required.
    private static func window(from value: Any?) -> Window? {
        guard
            let object = value as? [String: Any],
            let used = (object["used_percentage"] as? NSNumber)?.doubleValue
        else {
            return nil
        }
        let resets = (object["resets_at"] as? NSNumber)?.doubleValue
        return Window(usedPercent: used, resetsAt: resets.map { Date(timeIntervalSince1970: $0) })
    }

    // MARK: - Saying it out loud

    /// "还有 1 小时 40 分" — a duration, not a clock time. Both windows roll
    /// rather than landing on the hour, so "3 点 47 分重置" would be a number
    /// nobody can act on.
    private static func phrase(untilReset date: Date?, now: Date = Date()) -> String {
        guard let date else { return "不知道什么时候" }
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return "随时" }
        return "还有 " + duration(remaining)
    }

    private static func phrase(forAge age: TimeInterval) -> String {
        duration(age) + "前"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "不到 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }

        let hours = minutes / 60
        let rest = minutes % 60
        if hours < 24 {
            return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
        }
        return "\(hours / 24) 天\(hours % 24 == 0 ? "" : " \(hours % 24) 小时")"
    }
}

private struct Reading {
    let takenAt: Date
    let fiveHour: Window?
    let sevenDay: Window?
}

private struct Window {
    let usedPercent: Double
    let resetsAt: Date?
}
