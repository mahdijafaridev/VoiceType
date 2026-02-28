import SwiftUI

/**
 Application entry point for the menu bar utility.

 This app intentionally has no main window and runs through an `NSStatusItem`.
 */
@main
struct VoiceTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
