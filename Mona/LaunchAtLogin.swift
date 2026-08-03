//
//  LaunchAtLogin.swift
//  Mona
//

import AppKit
import ServiceManagement

/// Whether Mona comes back on its own after a restart.
///
/// Deliberately not a `UserDefaults` flag. The registration lives with the
/// system, and it can change without us: you can remove Mona from 登录项与扩展
/// at any time, and macOS can leave a fresh registration sitting in
/// `.requiresApproval` until you say yes. A stored copy of "the user ticked the
/// box" would drift out of step with all of that and show a tick for something
/// that is not going to happen. So the switch reads the real status every time
/// and reports what it finds.
enum LaunchAtLogin {
    /// Four states, only three of which mean anything distinct here:
    /// `.enabled` is on, `.requiresApproval` is on-but-waiting-for-you, and
    /// `.notRegistered` / `.notFound` are both off — the second only says the
    /// system has never held a record for this bundle, which is what a copy
    /// that has never been switched on looks like.
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Throws rather than swallowing: a switch that silently springs back gives
    /// no clue why, and the reason is the only useful thing to say.
    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// The pane where a `.requiresApproval` registration is waiting.
    static func openLoginItemsSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        )
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
