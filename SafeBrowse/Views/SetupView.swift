import SwiftUI

/// Shown when the helper daemon is not running. Walks the user through installation.
struct SetupView: View {
    @EnvironmentObject var state: AppState

    @State private var installState: InstallState = .idle

    enum InstallState {
        case idle, running, success, failure(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
                .animation(.default, value: installState.label)

            Text(title)
                .font(.title.bold())

            Text(subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()

            switch installState {
            case .running:
                ProgressView("Installing helper…")
                    .padding()

            case .success:
                Label("Installed successfully!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Button("Connect Now") { state.startPolling() }
                    .buttonStyle(.borderedProminent)

            case .failure(let msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                manualFallback

            case .idle:
                VStack(spacing: 16) {
                    Button("Install Helper…") { runInstall() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    Text("Requires your Mac login password once to set up the DNS proxy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Divider()

                    manualFallback
                }
            }
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 380)
    }

    // MARK: - Install

    private func runInstall() {
        let appPath = Bundle.main.bundlePath
        let scriptPath = "\(appPath)/Contents/Resources/install.sh"

        // Escape single quotes in paths (safety measure)
        let escapedScript = scriptPath.replacingOccurrences(of: "'", with: "'\\''")
        let escapedApp    = appPath.replacingOccurrences(of: "'", with: "'\\''")

        let appleScriptSrc = """
        do shell script "'\(escapedScript)' '\(escapedApp)'" with administrator privileges
        """

        installState = .running

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let script = NSAppleScript(source: appleScriptSrc)
            script?.executeAndReturnError(&error)

            DispatchQueue.main.async {
                if let err = error {
                    let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Unknown error."
                    // Error code 0 = user cancelled the password dialog
                    let code = err[NSAppleScript.errorNumber] as? Int ?? -1
                    if code == -128 {
                        installState = .idle   // user cancelled — reset silently
                    } else {
                        installState = .failure(msg)
                    }
                } else {
                    installState = .success
                }
            }
        }
    }

    // MARK: - Manual fallback (for advanced users)

    private var manualFallback: some View {
        DisclosureGroup("Manual install (Terminal)") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Run this command in Terminal:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(installCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                    }
                    .font(.caption)
                    Spacer()
                    Button("Retry Connection") { state.startPolling() }
                        .font(.caption)
                }
            }
            .padding(.top, 6)
        }
        .font(.caption)
        .frame(maxWidth: 480)
    }

    private var installCommand: String {
        "sudo \"\(Bundle.main.bundlePath)/Contents/Resources/install.sh\" \"\(Bundle.main.bundlePath)\""
    }

    // MARK: - Computed appearance

    private var icon: String {
        switch installState {
        case .idle, .running: return "exclamationmark.shield"
        case .success:        return "checkmark.shield.fill"
        case .failure:        return "xmark.shield.fill"
        }
    }

    private var iconColor: Color {
        switch installState {
        case .idle, .running: return .orange
        case .success:        return .green
        case .failure:        return .red
        }
    }

    private var title: String {
        switch installState {
        case .idle:    return "Helper Not Running"
        case .running: return "Installing…"
        case .success: return "Ready to Connect"
        case .failure: return "Installation Failed"
        }
    }

    private var subtitle: String {
        switch installState {
        case .idle:
            return "SafeBrowse needs a privileged helper to intercept DNS on port 53. Click below to install it — you'll be asked for your Mac login password once."
        case .running:
            return "Setting up the DNS proxy daemon…"
        case .success:
            return "The helper daemon is installed and running."
        case .failure:
            return "The install script encountered an error. Try the manual command below."
        }
    }
}

extension SetupView.InstallState {
    var label: String {
        switch self {
        case .idle:        return "idle"
        case .running:     return "running"
        case .success:     return "success"
        case .failure:     return "failure"
        }
    }
}
