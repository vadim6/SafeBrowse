import SwiftUI
import AppKit

// MARK: - Application delegate (intercepts all quit paths)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let pm = PasswordManager()
        guard pm.isPasswordSet else { return .terminateNow }

        var errorText = ""
        repeat {
            let alert = NSAlert()
            alert.messageText = "Quit SafeBrowse?"
            alert.informativeText = errorText.isEmpty
                ? "Enter the SafeBrowse password to quit."
                : errorText
            alert.alertStyle = .warning

            let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            alert.accessoryView = input
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")

            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

            if pm.verifyPassword(input.stringValue) { return .terminateNow }
            errorText = "Incorrect password. Try again."
        } while true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // keep running as menu bar app
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Catch all catchable termination signals and exit uncleanly (code 1)
        // so launchd's SuccessfulExit:false restarts the app.
        // The only clean exit(0) path is through applicationShouldTerminate above.
        // SIGKILL cannot be caught — launchd handles restart for that automatically.
        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            signal(sig) { _ in exit(1) }
        }
    }
}

// MARK: - App entry point

@main
struct SafeBrowseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        // Menu bar icon + popover
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
        } label: {
            // Icon changes based on protection state
            let imageName = !state.isConnected
                ? "shield.slash"
                : (state.isBlocking ? "shield.fill" : "shield.slash.fill")
            Image(systemName: imageName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    !state.isConnected ? .gray :
                    state.isBlocking   ? .green : .orange
                )
        }
        .menuBarExtraStyle(.window)

        // Main window (opened from menu bar)
        Window("SafeBrowse", id: "main") {
            MainView()
                .environmentObject(state)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 700, height: 520)
    }
}
