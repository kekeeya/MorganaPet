//
//  MonaApp.swift
//  Mona
//

import SwiftUI

@main
struct MonaApp: App {
    @NSApplicationDelegateAdaptor(DesktopPetAppDelegate.self) private var appDelegate

    var body: some Scene {
        // The Settings scene stays empty on purpose. An accessory app has no menu
        // bar to reach it from, and `showSettingsWindow:` needs a responder the
        // scene only installs when there is a window to install it on — so the
        // settings window is built and shown by the delegate instead.
        Settings {
            EmptyView()
        }
    }
}
