import Foundation

/// Thread-safe store for blocked and allowed domains.
/// Supports both hosts-file format and plain one-domain-per-line lists.
final class BlocklistStore {

    private var blocked: Set<String> = []
    private var allowed: Set<String> = []
    private let queue = DispatchQueue(label: "com.safebrowse.blocklist", attributes: .concurrent)

    var domainCount: Int { queue.sync { blocked.count } }

    // MARK: - Loading

    func load(blocklistPath: String, allowlistPath: String) {
        // Parse on a background queue WITHOUT holding the barrier — reads continue
        // uninterrupted against the old data while the new set is being built.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            var newBlocked: Set<String> = []
            var newAllowed: Set<String> = []

            if let content = try? String(contentsOfFile: blocklistPath, encoding: .utf8) {
                for line in content.components(separatedBy: .newlines) {
                    if let domain = Self.parseDomain(from: line) {
                        newBlocked.insert(domain)
                    }
                }
            }

            if let content = try? String(contentsOfFile: allowlistPath, encoding: .utf8) {
                for line in content.components(separatedBy: .newlines) {
                    let d = line.trimmingCharacters(in: .whitespaces).lowercased()
                    if !d.isEmpty, !d.hasPrefix("#") { newAllowed.insert(d) }
                }
            }

            newBlocked.subtract(newAllowed)

            // Hold the barrier only for the quick atomic pointer swap (~microseconds).
            self.queue.async(flags: .barrier) { [weak self] in
                guard let self else { return }
                self.blocked = newBlocked
                self.allowed = newAllowed
                NSLog("[Blocklist] Loaded %d blocked, %d allowed", newBlocked.count, newAllowed.count)
            }
        }
    }

    // MARK: - Lookup

    /// Returns true if `domain` (or any of its parent domains) is blocked and not explicitly allowed.
    func isBlocked(_ domain: String) -> Bool {
        checkDomain(domain).isBlocked
    }

    /// Returns both the blocked status and which rule matched (for debug / UI).
    func checkDomain(_ domain: String) -> (isBlocked: Bool, matchedRule: String?) {
        let lower = domain.lowercased()
        return queue.sync {
            if allowed.contains(lower) { return (false, nil) }
            if blocked.contains(lower) { return (true, lower) }

            // Walk up the hierarchy: sub.evil.com → evil.com → com
            var parts = lower.components(separatedBy: ".")
            while parts.count > 1 {
                parts.removeFirst()
                let parent = parts.joined(separator: ".")
                if blocked.contains(parent) { return (true, parent) }
            }
            return (false, nil)
        }
    }

    // MARK: - Parsing

    private static func parseDomain(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("!"), !trimmed.hasPrefix(";") else { return nil }

        // AdBlock / AdGuard format: "||evil.com^" or "||evil.com^$options"
        if trimmed.hasPrefix("||") {
            var rule = trimmed.dropFirst(2)
            if let caret = rule.firstIndex(of: "^") {
                rule = rule[rule.startIndex ..< caret]
            }
            let domain = String(rule).lowercased()
            return isValidDomain(domain) ? domain : nil
        }

        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        switch parts.count {
        case 2...:
            // Hosts format: "0.0.0.0 evil.com" or "127.0.0.1 evil.com" or ":: evil.com"
            let addr = parts[0]
            guard addr == "0.0.0.0" || addr == "127.0.0.1" || addr == "::" else { return nil }
            let domain = parts[1].lowercased()
            guard domain != "localhost", domain != "localhost.localdomain" else { return nil }
            return isValidDomain(domain) ? domain : nil
        case 1:
            // Plain domain
            let domain = parts[0].lowercased()
            return isValidDomain(domain) ? domain : nil
        default:
            return nil
        }
    }

    private static func isValidDomain(_ domain: String) -> Bool {
        guard domain.contains("."), !domain.contains(" "), domain.count <= 253 else { return false }
        // Reject raw IP addresses
        let isIP = domain.allSatisfy { $0.isNumber || $0 == "." }
        return !isIP
    }
}
