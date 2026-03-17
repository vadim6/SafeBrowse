import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// UDP DNS proxy that listens on 127.0.0.1:53.
/// Blocked domains receive an NXDOMAIN response; all others are forwarded upstream.
final class DNSProxy {

    private let store: BlocklistStore
    private(set) var isBlockingEnabled: Bool = true
    private var blockedToday: Int = 0
    private let statsQueue = DispatchQueue(label: "com.safebrowse.stats")
    private(set) var upstreamServers: [String] = ["1.1.1.1", "8.8.8.8"]
    private var serverSocket: Int32 = -1
    private var isRunning = false

    // Hard-cap concurrent query handlers so blocking forward() calls can't spawn
    // unbounded threads (GCD creates one thread per blocked task on an uncapped queue).
    private static let queryQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 32
        q.qualityOfService = .userInitiated
        q.name = "com.safebrowse.dns.queries"
        return q
    }()

    init(store: BlocklistStore) {
        self.store = store
    }

    var currentBlockedToday: Int { statsQueue.sync { blockedToday } }

    func setBlocking(_ enabled: Bool) {
        isBlockingEnabled = enabled
        NSLog("[DNSProxy] Blocking %@", enabled ? "enabled" : "disabled")
    }

    func setUpstreamServers(_ servers: [String]) {
        upstreamServers = servers.isEmpty ? ["1.1.1.1", "8.8.8.8"] : servers
    }

    func resetDailyStats() {
        statsQueue.async(flags: .barrier) { self.blockedToday = 0 }
    }

    // MARK: - Lifecycle

    func start() throws {
        serverSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard serverSocket >= 0 else { throw Error.socketCreationFailed(errno) }

        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(53).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(serverSocket)
            throw Error.bindFailed(errno)
        }

        isRunning = true
        NSLog("[DNSProxy] Listening on 127.0.0.1:53")
        Thread.detachNewThread { [weak self] in self?.receiveLoop() }
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 { close(serverSocket); serverSocket = -1 }
    }

    // MARK: - Receive loop

    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        while isRunning {
            let n = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(serverSocket, &buffer, buffer.count, 0, $0, &addrLen)
                }
            }
            guard n > 0 else { continue }

            let query = Data(buffer[0 ..< n])
            let capturedAddr = clientAddr
            let sock = serverSocket

            Self.queryQueue.addOperation { [weak self] in
                self?.handle(query: query, clientAddr: capturedAddr, socket: sock)
            }
        }
    }

    // MARK: - Query handling

    private func handle(query: Data, clientAddr: sockaddr_in, socket: Int32) {
        guard DNSMessage.isQuery(query) else { return }

        let response: Data

        if isBlockingEnabled, let domain = DNSMessage.extractQueryName(from: query),
           store.isBlocked(domain) {
            statsQueue.async(flags: .barrier) { self.blockedToday += 1 }
            NSLog("[DNSProxy] Blocked: %@", domain)
            response = DNSMessage.buildNXDOMAINResponse(for: query)
        } else {
            response = forwardToUpstream(query) ?? DNSMessage.buildNXDOMAINResponse(for: query)
        }

        sendResponse(response, to: clientAddr, socket: socket)
    }

    private func sendResponse(_ data: Data, to addr: sockaddr_in, socket: Int32) {
        var bytes = Array(data)
        var dest = addr
        withUnsafePointer(to: &dest) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = sendto(socket, &bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    // MARK: - Upstream forwarding

    private func forwardToUpstream(_ query: Data) -> Data? {
        for server in upstreamServers {
            if let response = forward(query, to: server) { return response }
        }
        return nil
    }

    private func forward(_ query: Data, to server: String) -> Data? {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(53).bigEndian
        dest.sin_addr.s_addr = inet_addr(server)

        var queryBytes = Array(query)
        let sent = withUnsafePointer(to: &dest) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(sock, &queryBytes, queryBytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: 4096)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = withUnsafeMutablePointer(to: &srcAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(sock, &buf, buf.count, 0, $0, &srcLen)
            }
        }
        guard received > 0 else { return nil }
        return Data(buf[0 ..< received])
    }

    // MARK: - Errors

    enum Error: Swift.Error {
        case socketCreationFailed(Int32)
        case bindFailed(Int32)
    }
}
