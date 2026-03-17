import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published var isConnected: Bool = false
    @Published var isBlocking: Bool = true
    @Published var blockedToday: Int = 0
    @Published var domainCount: Int = 0
    @Published var upstreamDNS: [String] = ["1.1.1.1", "8.8.8.8"]

    @Published var isPaused: Bool = false
    @Published var pauseSecondsRemaining: Int = 0
    @Published var pauseSheetRequested: Bool = false

    @Published var blocklists: [BlocklistSource] = BlocklistSource.defaults
    @Published var allowlist: [String] = []
    @Published var customBlocklist: [String] = []

    @Published var isUpdatingBlocklists: Bool = false
    @Published var lastBlocklistUpdate: Date? = nil
    @Published var updateError: String? = nil

    // MARK: - Dependencies

    private let client = HelperClient()
    private let downloader = BlocklistDownloader()
    private var statusTimer: Timer?
    private var pauseTimer: Timer?
    private var hasSyncedDNS = false

    // MARK: - Initialisation

    init() {
        loadSettings()
        startPolling()
    }

    // MARK: - Helper connection

    func startPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollStatus() }
        }
        pollStatus()
    }

    private func pollStatus() {
        client.send(.getStatus) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch response {
                case .status(let isEnabled, let blockedToday, let domainCount, let upstreamDNS):
                    self.isConnected = true
                    self.isBlocking = isEnabled
                    self.blockedToday = blockedToday
                    self.domainCount = domainCount
                    if !self.hasSyncedDNS {
                        self.upstreamDNS = upstreamDNS
                        self.hasSyncedDNS = true
                    }
                case .error:
                    self.isConnected = false
                    self.hasSyncedDNS = false
                default:
                    break
                }
            }
        }
    }

    // MARK: - Blocking control

    func enableBlocking() {
        isPaused = false
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseSecondsRemaining = 0
        client.send(.enableBlocking, reply: nil)
        isBlocking = true
    }

    enum PauseDuration: String, CaseIterable, Identifiable {
        case thirtyMin = "30 minutes"
        case oneHour   = "1 hour"
        case twoHours  = "2 hours"
        case untilRestart = "Until restart"

        var id: String { rawValue }

        var seconds: Int? {
            switch self {
            case .thirtyMin:    return 30 * 60
            case .oneHour:      return 60 * 60
            case .twoHours:     return 2 * 60 * 60
            case .untilRestart: return nil
            }
        }
    }

    func pauseBlocking(for duration: PauseDuration) {
        isPaused = true
        isBlocking = false
        client.send(.disableBlocking, reply: nil)

        pauseTimer?.invalidate()
        if let seconds = duration.seconds {
            pauseSecondsRemaining = seconds
            pauseTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.pauseSecondsRemaining > 1 {
                        self.pauseSecondsRemaining -= 1
                    } else {
                        self.enableBlocking()
                    }
                }
            }
        }
    }

    // MARK: - DNS management

    func updateUpstreamDNS(_ servers: [String]) {
        let resolved = servers.isEmpty ? ["1.1.1.1", "8.8.8.8"] : servers
        upstreamDNS = resolved
        if let payload = try? JSONEncoder().encode(resolved),
           let str = String(data: payload, encoding: .utf8) {
            client.send(.updateUpstreamDNS, payload: str, reply: nil)
        }
    }

    // MARK: - Blocklist management

    func updateBlocklists() {
        isUpdatingBlocklists = true
        updateError = nil
        let enabled = blocklists.filter { $0.isEnabled }

        downloader.download(sources: enabled, extraDomains: customBlocklist) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isUpdatingBlocklists = false
                switch result {
                case .success(let counts):
                    var failedNames: [String] = []
                    for (id, count) in counts {
                        if let i = self.blocklists.firstIndex(where: { $0.id == id }) {
                            self.blocklists[i].domainCount = count
                            if count > 0 {
                                self.blocklists[i].lastUpdated = Date()
                            } else {
                                failedNames.append(self.blocklists[i].name)
                            }
                        }
                    }
                    self.lastBlocklistUpdate = Date()
                    self.client.send(.reloadBlocklist, reply: nil)
                    if !failedNames.isEmpty {
                        self.updateError = "0 domains loaded from: \(failedNames.joined(separator: ", "))"
                    }
                case .failure(let error):
                    self.updateError = error.localizedDescription
                }
                self.saveSettings()
            }
        }
    }

    func removeBlocklist(id: UUID) {
        blocklists.removeAll { $0.id == id }
        saveSettings()
        updateBlocklists()   // rebuild combined file without this source
    }

    func addCustomBlocklistEntry(_ domain: String) {
        let d = domain.lowercased().trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty, !customBlocklist.contains(d) else { return }
        customBlocklist.append(d)
        saveCustomBlocklist()
        updateBlocklists()
    }

    func removeCustomBlocklistEntry(_ domain: String) {
        customBlocklist.removeAll { $0 == domain }
        saveCustomBlocklist()
        updateBlocklists()
    }

    func addAllowlistEntry(_ domain: String) {
        let d = domain.lowercased().trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty, !allowlist.contains(d) else { return }
        allowlist.append(d)
        saveAllowlist()
        client.send(.reloadBlocklist, reply: nil)
    }

    func removeAllowlistEntry(_ domain: String) {
        allowlist.removeAll { $0 == domain }
        saveAllowlist()
        client.send(.reloadBlocklist, reply: nil)
    }

    // MARK: - Persistence

    private let settingsKey = "SafeBrowseSettings"

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(blocklists) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode([BlocklistSource].self, from: data) {
            blocklists = saved
        }
        loadAllowlist()
        loadCustomBlocklist()
    }

    private func saveAllowlist() {
        let content = allowlist.joined(separator: "\n")
        try? content.write(
            to: URL(fileURLWithPath: allowlistFilePath),
            atomically: true,
            encoding: .utf8
        )
    }

    private func saveCustomBlocklist() {
        let content = customBlocklist.joined(separator: "\n")
        try? content.write(
            to: URL(fileURLWithPath: customBlocklistFilePath),
            atomically: true, encoding: .utf8
        )
    }

    private func loadCustomBlocklist() {
        if let content = try? String(contentsOfFile: customBlocklistFilePath, encoding: .utf8) {
            customBlocklist = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
    }

    private func loadAllowlist() {
        if let content = try? String(contentsOfFile: allowlistFilePath, encoding: .utf8) {
            allowlist = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
    }
}
