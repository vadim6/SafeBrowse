import Foundation

final class BlocklistDownloader {

    typealias Completion = (Result<[UUID: Int], Error>) -> Void

    // URLSession configured with a browser-like User-Agent and a 60 s timeout.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300  // large files can take a while
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/537.36",
            "Accept-Encoding": "gzip, deflate, br",
        ]
        return URLSession(configuration: config)
    }()

    /// Downloads all enabled sources, merges them (+ any extra custom domains), writes to the shared blocklist file.
    func download(sources: [BlocklistSource], extraDomains: [String] = [], completion: @escaping Completion) {
        guard !sources.isEmpty || !extraDomains.isEmpty else {
            completion(.success([:])); return
        }

        let group = DispatchGroup()
        var perSource: [UUID: Set<String>] = [:]
        var sourceErrors: [String] = []
        let lock = NSLock()

        for source in sources {
            group.enter()
            downloadSource(source) { result in
                lock.lock()
                switch result {
                case .success(let domains):
                    perSource[source.id] = domains
                case .failure(let error):
                    sourceErrors.append("\(source.name): \(error.localizedDescription)")
                    perSource[source.id] = []
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .global()) {
            var merged: Set<String> = Set(extraDomains.map { $0.lowercased() })
            var counts: [UUID: Int] = [:]
            for (id, domains) in perSource {
                merged.formUnion(domains)
                counts[id] = domains.count
            }

            // If every source failed, surface the first error rather than writing an empty file.
            if merged.isEmpty, !sourceErrors.isEmpty {
                completion(.failure(DownloadError.allSourcesFailed(sourceErrors)))
                return
            }

            let content = merged.sorted().joined(separator: "\n")
            do {
                try content.write(
                    to: URL(fileURLWithPath: blocklistFilePath),
                    atomically: true,
                    encoding: .utf8
                )
                completion(.success(counts))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Single source

    private func downloadSource(
        _ source: BlocklistSource,
        completion: @escaping (Result<Set<String>, Error>) -> Void
    ) {
        guard let url = URL(string: source.url) else {
            completion(.failure(DownloadError.invalidURL(source.url)))
            return
        }

        session.dataTask(with: url) { data, response, error in
            if let error {
                completion(.failure(error)); return
            }
            guard let data else {
                completion(.failure(DownloadError.noData)); return
            }

            // Try UTF-8 first, fall back to Latin-1 (common in hosts files)
            let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""

            if text.isEmpty {
                completion(.failure(DownloadError.noData)); return
            }

            completion(.success(Self.parse(text)))
        }.resume()
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> Set<String> {
        var result: Set<String> = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("!"),
                  !trimmed.hasPrefix(";") else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            // Hosts format: "0.0.0.0 evil.com"
            if parts.count >= 2,
               parts[0] == "0.0.0.0" || parts[0] == "127.0.0.1" || parts[0] == "::" {
                let domain = parts[1].lowercased()
                if domain != "localhost", domain != "localhost.localdomain", isValid(domain) {
                    result.insert(domain)
                }
                continue
            }

            // AdBlock / AdGuard format: "||evil.com^" or "||evil.com^$options"
            // ||  = anchor at domain boundary
            // ^   = separator (end of domain or query string start)
            if trimmed.hasPrefix("||") {
                var rule = trimmed.dropFirst(2)          // strip "||"
                if let caret = rule.firstIndex(of: "^") {
                    rule = rule[rule.startIndex ..< caret]  // strip "^" and everything after
                }
                let domain = String(rule).lowercased()
                if isValid(domain) { result.insert(domain) }
                continue
            }

            // Plain domain (one per line)
            if parts.count == 1 {
                let domain = parts[0].lowercased()
                if isValid(domain) { result.insert(domain) }
            }
        }
        return result
    }

    private static func isValid(_ domain: String) -> Bool {
        guard domain.contains("."), domain.count <= 253, !domain.contains(" ") else { return false }
        return !domain.allSatisfy { $0.isNumber || $0 == "." }
    }

    // MARK: - Errors

    enum DownloadError: LocalizedError {
        case invalidURL(String)
        case noData
        case allSourcesFailed([String])

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url): return "Invalid URL: \(url)"
            case .noData:              return "Server returned no data"
            case .allSourcesFailed(let errors): return errors.joined(separator: "\n")
            }
        }
    }
}
