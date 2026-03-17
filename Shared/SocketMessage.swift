import Foundation

// MARK: - Commands (app → helper)

enum Command: String, Codable {
    case enableBlocking
    case disableBlocking
    case reloadBlocklist
    case getStatus
    case updateUpstreamDNS   // payload: JSON-encoded [String]
    case restoreSystemDNS    // used by uninstall
    case checkDomain         // payload: domain string → returns .domainCheck
    case quit
}

struct CommandMessage: Codable {
    let command: Command
    let payload: String?

    init(command: Command, payload: String? = nil) {
        self.command = command
        self.payload = payload
    }
}

// MARK: - Responses (helper → app)

enum Response: Codable {
    case ok
    case status(isEnabled: Bool, blockedToday: Int, domainCount: Int, upstreamDNS: [String])
    case domainCheck(domain: String, isBlocked: Bool, matchedRule: String?)
    case error(String)

    private enum CodingKeys: String, CodingKey {
        case type, isEnabled, blockedToday, domainCount, upstreamDNS
        case message, domain, isBlocked, matchedRule
    }

    private enum ResponseType: String, Codable {
        case ok, status, domainCheck, error
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ok:
            try c.encode(ResponseType.ok, forKey: .type)
        case .status(let isEnabled, let blockedToday, let domainCount, let upstreamDNS):
            try c.encode(ResponseType.status, forKey: .type)
            try c.encode(isEnabled, forKey: .isEnabled)
            try c.encode(blockedToday, forKey: .blockedToday)
            try c.encode(domainCount, forKey: .domainCount)
            try c.encode(upstreamDNS, forKey: .upstreamDNS)
        case .domainCheck(let domain, let isBlocked, let matchedRule):
            try c.encode(ResponseType.domainCheck, forKey: .type)
            try c.encode(domain, forKey: .domain)
            try c.encode(isBlocked, forKey: .isBlocked)
            try c.encodeIfPresent(matchedRule, forKey: .matchedRule)
        case .error(let message):
            try c.encode(ResponseType.error, forKey: .type)
            try c.encode(message, forKey: .message)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(ResponseType.self, forKey: .type)
        switch type {
        case .ok:
            self = .ok
        case .status:
            self = .status(
                isEnabled: try c.decode(Bool.self, forKey: .isEnabled),
                blockedToday: try c.decode(Int.self, forKey: .blockedToday),
                domainCount: try c.decode(Int.self, forKey: .domainCount),
                upstreamDNS: try c.decode([String].self, forKey: .upstreamDNS)
            )
        case .domainCheck:
            self = .domainCheck(
                domain: try c.decode(String.self, forKey: .domain),
                isBlocked: try c.decode(Bool.self, forKey: .isBlocked),
                matchedRule: try c.decodeIfPresent(String.self, forKey: .matchedRule)
            )
        case .error:
            self = .error(try c.decode(String.self, forKey: .message))
        }
    }
}

// MARK: - Shared paths

let socketPath = "/var/run/safebrowse.sock"
let dataDir = "/Library/Application Support/SafeBrowse"
let blocklistFilePath = dataDir + "/blocklist.txt"
let allowlistFilePath = dataDir + "/allowlist.txt"
let customBlocklistFilePath = dataDir + "/custom-blocklist.txt"
let configFilePath = dataDir + "/config.json"
