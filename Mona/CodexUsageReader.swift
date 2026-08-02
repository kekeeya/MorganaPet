//
//  CodexUsageReader.swift
//  Mona
//

import Foundation

enum PetExpression: String, CaseIterable {
    case regular
    case smile
    case kirakira
    case angry
    case sad
    case shocked
    case sleep
}

struct DialoguePage {
    let message: String
    let expression: PetExpression
}

/// Codex's own account of how much of your allowance is gone.
///
/// Read out of the session logs under `~/.codex/sessions`, which is an
/// undocumented internal format — unlike the Claude side, where the status line
/// is a documented handover. Codex offers no live source at all: the numbers are
/// whatever the last session happened to record, so a reading can be hours old
/// while the Codex app shows something quite different.
///
/// That gap is the thing to be honest about. A figure from this morning printed
/// as though it were current is how you end up trusting the wrong number, so the
/// age travels with the reading and he says it before he says the percentage.
enum CodexUsageReader {
    /// Remaining share above which he still counts the window as comfortable.
    private static let plentyRemainingPercent: Double = 50

    /// Past this the reading is old enough to lead with. Codex writes a record
    /// on every turn, so anything older means you have not used it since.
    static let staleAfter: TimeInterval = 30 * 60

    static func latestDialogue(now: Date = Date()) -> [DialoguePage] {
        let book = PetDialogueBook.shared
        guard let snapshot = latestSnapshot() else {
            return book.pages(for: .quotaUnavailable)
        }

        var pages: [DialoguePage] = []

        let age = now.timeIntervalSince(snapshot.recordedAt)
        if age >= staleAfter {
            pages += book.pages(for: .quotaStale).filling(["age": duration(age) + "前"])
        }

        for window in snapshot.windows {
            pages += self.pages(for: window, in: book, now: now)
        }

        // Records exist but carried no window we could read — same as nothing.
        return pages.isEmpty ? book.pages(for: .quotaUnavailable) : pages
    }

    private static func pages(
        for window: Window,
        in book: PetDialogueBook,
        now: Date
    ) -> [DialoguePage] {
        let name = phrase(forWindow: window.minutes)

        // The window already rolled over, so whatever was recorded has since
        // been forgiven. Reporting the old figure would be worse than silence.
        if let resets = window.resetsAt, resets <= now {
            return book.pages(for: .quotaExpired).filling(["window": name])
        }

        let used = min(max(window.usedPercent, 0), 100)
        let values = [
            "window": name,
            "used": used.formatted(.number.precision(.fractionLength(0...1))),
            "reset": clockPhrase(for: window.resetsAt)
        ]

        let scenario: PetDialogueScenario
        if used >= 100 {
            scenario = .quotaExhausted
        } else if 100 - used > plentyRemainingPercent {
            scenario = .quotaPlenty
        } else {
            scenario = .quotaLow
        }
        return book.pages(for: scenario).filling(values)
    }

    // MARK: - Saying it out loud

    /// Named from `window_minutes` rather than from which slot it arrived in.
    ///
    /// Codex reports its windows as `primary` and `secondary`, and neither name
    /// says how long it is: on this account `primary` is the weekly one, while
    /// other tools assume `primary` is the five-hour one. Both assumptions are
    /// guesses about a field that already carries the answer.
    private static func phrase(forWindow minutes: Double?) -> String {
        guard let minutes, minutes > 0 else { return "额度" }
        if abs(minutes - 10_080) <= 60 { return "本周" }
        if minutes >= 1_440 {
            let days = Int((minutes / 1_440).rounded())
            return "\(days) 天"
        }
        let hours = Int((minutes / 60).rounded())
        return hours >= 1 ? "\(hours) 小时" : "\(Int(minutes)) 分钟"
    }

    private static func clockPhrase(for date: Date?) -> String {
        guard let date else { return "未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }


    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "不到 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
        }
        return "\(hours / 24) 天"
    }

    // MARK: - Reading the logs

    /// Settings first, then `CODEX_HOME`, then the usual place.
    ///
    /// The environment variable is second rather than first because a copy
    /// launched from the Dock never sees it: GUI apps inherit the launchd
    /// environment, not the one your shell exports. It still works when Mona is
    /// started from a terminal, which is why it is honoured at all.
    static var codexHomeURL: URL {
        let configured = PetPreferences.codexHome
        if !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    static var sessionsURL: URL {
        codexHomeURL.appendingPathComponent("sessions", isDirectory: true)
    }

    /// What the settings window shows under the path: whether anything is
    /// actually there. "他说看不到" is otherwise indistinguishable between a
    /// wrong path, a missing install, and a Codex that has simply never run.
    static func probe(now: Date = Date()) -> (ok: Bool, detail: String) {
        let url = sessionsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (false, "目录不存在")
        }
        // The age of the newest reading, not a count of files. Age is what
        // actually goes wrong here — records are only written while Codex runs,
        // so "there are files" and "there is a recent number" are very different
        // answers, and only the second one means the panel will say anything
        // useful.
        guard let snapshot = latestSnapshot() else {
            return (false, "目录在，但没有额度记录")
        }
        return (true, "已找到额度信息，\(duration(now.timeIntervalSince(snapshot.recordedAt)))前。")
    }

    private static func latestSnapshot() -> Snapshot? {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]

        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let files = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.isRegularFile == true ? url : nil
        }
        .sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return left > right
        }

        for file in files.prefix(20) {
            if let snapshot = snapshot(from: file) {
                return snapshot
            }
        }
        return nil
    }

    private static func snapshot(from url: URL) -> Snapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        let readSize: UInt64 = 1_048_576
        try? handle.seek(toOffset: end > readSize ? end - readSize : 0)

        guard let data = try? handle.readToEnd() else {
            return nil
        }
        let text = String(decoding: data, as: UTF8.self)

        for line in text.split(separator: "\n").reversed() {
            guard
                let lineData = line.data(using: .utf8),
                let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                root["type"] as? String == "event_msg",
                let payload = root["payload"] as? [String: Any],
                payload["type"] as? String == "token_count",
                // Codex writes `rate_limits: null` on plenty of turns; those are
                // records without an answer, not records to give up on.
                let limits = payload["rate_limits"] as? [String: Any]
            else {
                continue
            }

            let windows = ["primary", "secondary"].compactMap { window(from: limits[$0]) }
            guard !windows.isEmpty else { continue }

            return Snapshot(
                recordedAt: timestamp(from: root["timestamp"])
                    ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    ?? .distantPast,
                windows: windows
            )
        }
        return nil
    }

    private static func window(from value: Any?) -> Window? {
        guard
            let object = value as? [String: Any],
            let used = (object["used_percent"] as? NSNumber)?.doubleValue
        else {
            return nil
        }
        let resets = (object["resets_at"] as? NSNumber)?.doubleValue
        return Window(
            usedPercent: used,
            minutes: (object["window_minutes"] as? NSNumber)?.doubleValue,
            resetsAt: resets.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func timestamp(from value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

private struct Snapshot {
    let recordedAt: Date
    let windows: [Window]
}

private struct Window {
    let usedPercent: Double
    let minutes: Double?
    let resetsAt: Date?
}
