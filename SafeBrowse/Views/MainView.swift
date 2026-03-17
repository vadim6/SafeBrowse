import SwiftUI

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab = 0
    @State private var showAbout = false
    @State private var showPause = false

    var body: some View {
        if !state.isConnected {
            SetupView()
                .environmentObject(state)
                .frame(minWidth: 540, minHeight: 420)
        } else {
            TabView(selection: $selectedTab) {
                StatusTab(showPause: $showPause)
                    .tabItem { Label("Status", systemImage: "shield.fill") }
                    .tag(0)

                BlocklistsView()
                    .tabItem { Label("Blocklists", systemImage: "list.bullet.rectangle") }
                    .tag(1)

                SettingsTab()
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(2)
            }
            .environmentObject(state)
            .frame(minWidth: 760, minHeight: 480)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAbout.toggle() } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showAbout, arrowEdge: .bottom) {
                        AboutPopover()
                    }
                }
            }
            .sheet(isPresented: $showPause) {
                PauseView().environmentObject(state)
            }
            .onAppear {
                if state.pauseSheetRequested {
                    selectedTab = 0
                    showPause = true
                    state.pauseSheetRequested = false
                }
            }
            .onChange(of: state.pauseSheetRequested) { requested in
                if requested {
                    selectedTab = 0
                    showPause = true
                    state.pauseSheetRequested = false
                }
            }
        }
    }
}

// MARK: - Status tab

private struct StatusTab: View {
    @EnvironmentObject var state: AppState
    @Binding var showPause: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Big shield
            ZStack {
                Circle()
                    .fill(state.isBlocking ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: state.isBlocking ? "shield.fill" : "shield.slash.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(state.isBlocking ? .green : .orange)
            }

            Text(state.isBlocking ? "Protection is On" : "Protection is Paused")
                .font(.title.bold())

            if state.isPaused, state.pauseSecondsRemaining > 0 {
                Text("Resumes in \(formatTime(state.pauseSecondsRemaining))")
                    .foregroundStyle(.orange)
            }

            // Stats grid
            HStack(spacing: 32) {
                StatBox(value: state.blockedToday.formatted(), label: "Blocked today", color: .red)
                StatBox(value: state.domainCount.formatted(), label: "Domains in list", color: .blue)
            }

            Spacer()

            Button(!state.isBlocking ? "Resume Protection" : "Pause Protection…") {
                if !state.isBlocking {
                    state.enableBlocking()
                } else {
                    showPause = true
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(!state.isBlocking ? .green : .orange)
            .controlSize(.large)

            if state.isBlocking {
                Text("Pausing also unlocks blocklist settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
    }

    private func formatTime(_ s: Int) -> String {
        let m = s / 60; let sec = s % 60
        return m > 0 ? "\(m)m \(sec)s" : "\(sec)s"
    }
}

private struct StatBox: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140, height: 70)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)))
    }
}

// MARK: - Settings tab

private struct SettingsTab: View {
    @EnvironmentObject var state: AppState
    @State private var dnsInput = ""
    @State private var showChangePassword = false
    private let pm = PasswordManager()

    var body: some View {
        Form {
            Section("Upstream DNS Servers") {
                ForEach(state.upstreamDNS, id: \.self) { server in
                    HStack {
                        Text(server).font(.body.monospaced())
                        Spacer()
                        Button {
                            let updated = state.upstreamDNS.filter { $0 != server }
                            state.updateUpstreamDNS(updated)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Add server (e.g. 9.9.9.9)", text: $dnsInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addDNSServer() }
                    Button { addDNSServer() } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(dnsInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Password") {
                if pm.isPasswordSet {
                    Button("Change Password…") { showChangePassword = true }
                } else {
                    Button("Set Password…") { showChangePassword = true }
                }
            }

            Section("Blocklist") {
                LabeledContent("Last updated") {
                    if let d = state.lastBlocklistUpdate {
                        Text(d, style: .relative) + Text(" ago")
                    } else {
                        Text("Never")
                    }
                }
                Button("Update Now") { state.updateBlocklists() }
                    .disabled(state.isUpdatingBlocklists)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet(isPresented: $showChangePassword)
        }
    }

    private func addDNSServer() {
        let server = dnsInput.trimmingCharacters(in: .whitespaces)
        guard !server.isEmpty, !state.upstreamDNS.contains(server) else { return }
        state.updateUpstreamDNS(state.upstreamDNS + [server])
        dnsInput = ""
    }
}

// MARK: - About popover (shared with MenuBarView)

struct AboutPopover: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Vibe coded with Claude Code 🤖")
                .font(.caption.bold())
            Text("by Vadim Freger")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link(destination: URL(string: "https://github.com/vadim6/SafeBrowse")!) {
                HStack(spacing: 5) {
                    Image("GitHubMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                    Text("GitHub")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }
}

private struct ChangePasswordSheet: View {
    @Binding var isPresented: Bool
    @State private var current = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var error = ""
    private let pm = PasswordManager()

    var body: some View {
        VStack(spacing: 16) {
            Text("Change Password").font(.headline)

            if pm.isPasswordSet {
                SecureField("Current password", text: $current)
                    .textFieldStyle(.roundedBorder)
            }
            SecureField("New password", text: $new1).textFieldStyle(.roundedBorder)
            SecureField("Confirm new password", text: $new2).textFieldStyle(.roundedBorder)

            if !error.isEmpty {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Save") {
                    if pm.isPasswordSet, !pm.verifyPassword(current) {
                        error = "Current password is incorrect."
                        return
                    }
                    guard new1 == new2 else { error = "Passwords don't match."; return }
                    guard new1.count >= 4 else { error = "Must be at least 4 characters."; return }
                    pm.setPassword(new1)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
