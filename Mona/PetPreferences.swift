//
//  PetPreferences.swift
//  Mona
//

import Foundation

/// Which of the things he can look up you actually want him offering.
///
/// Each reader depends on something not everyone has — a Codex install, a Claude
/// subscription — and an entry that only ever answers "吾辈看不到" is worse than
/// no entry. Rather than guess from whether the data happens to be readable
/// right now, the menu is yours to compose.
enum PetPreferences {
    static let showsCodexUsageKey = "MonaShowsCodexUsage"
    static let showsClaudeUsageKey = "MonaShowsClaudeUsage"
    static let showsMachineStatusKey = "MonaShowsMachineStatus"

    /// Where to look, when the usual place is not the right one.
    ///
    /// Both readers accept an override because both defaults can be wrong: Codex
    /// honours `CODEX_HOME`, which a copy launched from the Dock never sees — it
    /// inherits the launchd environment, not your shell's — and the Claude status
    /// line writes wherever you told it to. An empty string means "use the
    /// default", so clearing the field is how you go back.
    static let codexHomeKey = "MonaCodexHome"
    static let claudeStatusLineKey = "MonaClaudeStatusLine"

    /// How the menu-bar run cycle reads the machine.
    ///
    /// Taste, not correctness: whether a busy machine should make him hurry or
    /// slow to a trudge is a reading of what the icon is *for*.
    static let statusRunReversedKey = "MonaStatusRunReversed"

    /// Read on every frame rather than cached: the animator is already awake,
    /// a `UserDefaults.bool` is a dictionary lookup, and this way a flipped
    /// switch takes effect within one frame without anything to observe.
    static var statusRunReversed: Bool {
        UserDefaults.standard.bool(forKey: statusRunReversedKey)
    }

    static var codexHome: String {
        absolutePath(forKey: codexHomeKey)
    }

    static var claudeStatusLine: String {
        absolutePath(forKey: claudeStatusLineKey)
    }

    /// An override is only honoured when it is an absolute path.
    ///
    /// `URL(fileURLWithPath:)` resolves anything else against the working
    /// directory, which for a launched app is `/` — so a stray "1" in the field
    /// silently becomes `/1`, and everything downstream reports a missing file
    /// while pointing at a path nobody typed. Falling back to the default is the
    /// honest reading of a value that cannot mean what it says.
    private static func absolutePath(forKey key: String) -> String {
        let raw = (UserDefaults.standard.string(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        let expanded = (raw as NSString).expandingTildeInPath
        // A bare "/" is absolute and still meaningless as a target — it is what
        // a single stray keystroke leaves behind, not something anyone chose.
        return isPlausible(expanded) ? expanded : ""
    }

    /// Whether the field holds something that will simply be ignored, so the
    /// settings window can say so instead of leaving you to wonder why a path you
    /// typed had no effect.
    static func isUsablePath(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || isPlausible((trimmed as NSString).expandingTildeInPath)
    }

    private static func isPlausible(_ expanded: String) -> Bool {
        expanded.hasPrefix("/") && (expanded as NSString).lastPathComponent.isEmpty == false
            && expanded != "/"
    }

    /// All three lookups start on, so a fresh install shows everything and you
    /// turn off what does not apply to you. Registered rather than left to
    /// `UserDefaults.bool`, which reports an unset key as `false` — the opposite
    /// of what an absent preference should mean here.
    ///
    /// The run-cycle switch is the other way round: `false` is the shipped
    /// behaviour, so an unset key already means the right thing and it is
    /// registered only to keep the list of what exists in one place.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showsCodexUsageKey: true,
            showsClaudeUsageKey: true,
            showsMachineStatusKey: true,
            codexHomeKey: "",
            claudeStatusLineKey: "",
            statusRunReversedKey: false
        ])
    }
}
