import SwiftUI

/// Content of the MenuBarExtra popover/menu.
struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var showAbout = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            // Stats
            HStack {
                Label("\(state.blockedToday) blocked today", systemImage: "xmark.shield")
                Spacer()
                Label("\(state.domainCount.formatted()) domains", systemImage: "list.bullet")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Actions
            Button {
                if !state.isBlocking {
                    state.enableBlocking()
                } else {
                    state.pauseSheetRequested = true
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Label(!state.isBlocking ? "Resume Protection" : "Pause Protection…",
                      systemImage: !state.isBlocking ? "play.circle" : "pause.circle")
            }
            .disabled(!state.isConnected)
            .padding(.horizontal)
            .padding(.vertical, 6)

            if state.isPaused, state.pauseSecondsRemaining > 0 {
                Text("Resumes in \(formatTime(state.pauseSecondsRemaining))")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Divider()

            Button("Open SafeBrowse…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
                .padding(.horizontal)
                .padding(.vertical, 6)

            Button("Quit SafeBrowse…") { NSApp.terminate(nil) }
                .padding(.horizontal)
                .padding(.vertical, 6)
        }
        .frame(width: 280)

        // About button — bottom-right corner
        Button { showAbout.toggle() } label: {
            Text("?")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .padding(8)
        .popover(isPresented: $showAbout, arrowEdge: .bottom) {
            AboutPopover()
        }

        } // end ZStack
    }

    // MARK: - Computed

    private var statusIcon: String {
        if !state.isConnected { return "exclamationmark.triangle.fill" }
        return state.isBlocking ? "shield.fill" : "shield.slash.fill"
    }

    private var statusColor: Color {
        if !state.isConnected { return .gray }
        return state.isBlocking ? .green : .orange
    }

    private var statusTitle: String {
        if !state.isConnected { return "Helper not running" }
        return state.isBlocking ? "Protection On" : "Protection Paused"
    }

    private var statusSubtitle: String {
        if !state.isConnected { return "Run install.sh to set up the daemon" }
        return state.isBlocking
            ? "Blocking \(state.domainCount.formatted()) domains"
            : "All DNS requests are forwarded"
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

