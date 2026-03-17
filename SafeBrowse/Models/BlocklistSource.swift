import Foundation

struct BlocklistSource: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var url: String
    var isEnabled: Bool
    var lastUpdated: Date?
    var domainCount: Int

    init(id: UUID = UUID(), name: String, url: String, isEnabled: Bool = true,
         lastUpdated: Date? = nil, domainCount: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        self.lastUpdated = lastUpdated
        self.domainCount = domainCount
    }

    // MARK: - Built-in sources

    static let defaults: [BlocklistSource] = [
        BlocklistSource(
            name: "OISD Basic",
            url: "https://hosts.oisd.nl/basic/",
            isEnabled: true
        ),
        BlocklistSource(
            name: "Steven Black (ads + malware)",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
            isEnabled: true
        ),
        BlocklistSource(
            name: "Hagezi Pro",
            url: "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt",
            isEnabled: false
        ),
        BlocklistSource(
            name: "NSFW",
            url: "https://raw.githubusercontent.com/sjhgvr/oisd/main/domainswild2_nsfw.txt",
            isEnabled: false
        ),
    ]
}
