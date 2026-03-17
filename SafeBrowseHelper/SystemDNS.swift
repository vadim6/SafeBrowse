import Foundation

/// Manages macOS system DNS settings via `networksetup`.
/// On enable, sets all active network services to use 127.0.0.1.
/// On restore, reverts each service to its original DNS configuration.
final class SystemDNS {

    private let backupPath: String
    private var savedSettings: [String: [String]] = [:]

    init(dataDir: String) {
        self.backupPath = dataDir + "/dns-backup.json"
        loadBackup()
    }

    // MARK: - Public API

    func enableLocalDNS() {
        let services = activeNetworkServices()
        NSLog("[SystemDNS] Configuring %d service(s)", services.count)

        for service in services {
            if savedSettings[service] == nil {
                savedSettings[service] = currentDNS(for: service)
            }
            run("/usr/sbin/networksetup", args: ["-setdnsservers", service, "127.0.0.1"])
        }

        saveBackup()
        flushCache()
        NSLog("[SystemDNS] DNS set to 127.0.0.1")
    }

    func restoreSystemDNS() {
        for (service, servers) in savedSettings {
            if servers.isEmpty {
                run("/usr/sbin/networksetup", args: ["-setdnsservers", service, "empty"])
            } else {
                run("/usr/sbin/networksetup", args: ["-setdnsservers", service] + servers)
            }
        }
        savedSettings = [:]
        saveBackup()
        flushCache()
        NSLog("[SystemDNS] DNS restored to original settings")
    }

    // MARK: - Helpers

    private func activeNetworkServices() -> [String] {
        let output = run("/usr/sbin/networksetup", args: ["-listallnetworkservices"])
        return output
            .components(separatedBy: .newlines)
            .dropFirst()   // first line is a header
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                // Disabled services are prefixed with *
                let name = trimmed.hasPrefix("*") ? String(trimmed.dropFirst()) : trimmed
                return name
            }
    }

    private func currentDNS(for service: String) -> [String] {
        let output = run("/usr/sbin/networksetup", args: ["-getdnsservers", service])
        if output.contains("There aren't any DNS Servers") { return [] }
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("There aren't") }
    }

    private func flushCache() {
        run("/usr/bin/dscacheutil", args: ["-flushcache"])
        run("/bin/launchctl", args: ["kickstart", "-k", "system/com.apple.mDNSResponder"])
    }

    @discardableResult
    private func run(_ path: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - Persistence

    private func loadBackup() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: backupPath)),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }
        savedSettings = decoded
    }

    private func saveBackup() {
        if let data = try? JSONEncoder().encode(savedSettings) {
            try? data.write(to: URL(fileURLWithPath: backupPath))
        }
    }
}
