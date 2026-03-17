import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Unix-domain socket server that accepts commands from SafeBrowse.app.
final class SocketServer {

    private let path: String
    private let proxy: DNSProxy
    private let store: BlocklistStore
    private let sysDNS: SystemDNS
    private let blocklistPath: String
    private let allowlistPath: String

    private var serverSocket: Int32 = -1
    private var isRunning = false

    init(
        path: String,
        proxy: DNSProxy,
        store: BlocklistStore,
        sysDNS: SystemDNS,
        blocklistPath: String,
        allowlistPath: String
    ) {
        self.path = path
        self.proxy = proxy
        self.store = store
        self.sysDNS = sysDNS
        self.blocklistPath = blocklistPath
        self.allowlistPath = allowlistPath
    }

    // MARK: - Lifecycle

    func start() throws {
        unlink(path)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { throw Err.socketCreationFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            path.withCString { src in
                let len = min(strlen(src) + 1, dst.count)
                dst.copyBytes(from: UnsafeRawBufferPointer(start: src, count: len))
            }
        }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { close(serverSocket); throw Err.bindFailed(errno) }

        chmod(path, 0o666)  // allow non-root app to connect

        guard listen(serverSocket, 5) == 0 else { close(serverSocket); throw Err.listenFailed }

        isRunning = true
        NSLog("[SocketServer] Listening at %@", path)
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 { close(serverSocket); serverSocket = -1 }
        unlink(path)
    }

    // MARK: - Accept loop

    private func acceptLoop() {
        while isRunning {
            let client = accept(serverSocket, nil, nil)
            guard client >= 0 else { continue }
            Thread.detachNewThread { [weak self] in
                self?.handleClient(client)
                close(client)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = recv(fd, &buf, buf.count - 1, 0)
        guard n > 0 else { return }

        let data = Data(buf[0 ..< n])
        guard let msg = try? JSONDecoder().decode(CommandMessage.self, from: data) else {
            send(response: .error("Invalid command"), to: fd)
            return
        }
        send(response: handle(msg), to: fd)
    }

    // MARK: - Command dispatch

    private func handle(_ msg: CommandMessage) -> Response {
        switch msg.command {

        case .enableBlocking:
            proxy.setBlocking(true)
            sysDNS.enableLocalDNS()
            saveConfig()
            return .ok

        case .disableBlocking:
            proxy.setBlocking(false)
            saveConfig()
            return .ok

        case .reloadBlocklist:
            store.load(blocklistPath: blocklistPath, allowlistPath: allowlistPath)
            return .ok

        case .getStatus:
            return .status(
                isEnabled: proxy.isBlockingEnabled,
                blockedToday: proxy.currentBlockedToday,
                domainCount: store.domainCount,
                upstreamDNS: proxy.upstreamServers
            )

        case .updateUpstreamDNS:
            if let payload = msg.payload,
               let servers = try? JSONDecoder().decode([String].self, from: Data(payload.utf8)) {
                proxy.setUpstreamServers(servers)
                saveConfig()
            }
            return .ok

        case .checkDomain:
            let domain = msg.payload ?? ""
            let result = store.checkDomain(domain)
            return .domainCheck(domain: domain, isBlocked: result.isBlocked, matchedRule: result.matchedRule)

        case .restoreSystemDNS:
            sysDNS.restoreSystemDNS()
            return .ok

        case .quit:
            sysDNS.restoreSystemDNS()
            stop()
            exit(0)
        }
    }

    private func send(response: Response, to fd: Int32) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(UInt8(ascii: "\n"))
        _ = data.withUnsafeBytes { ptr in
            Foundation.send(fd, ptr.baseAddress!, ptr.count, 0)
        }
    }

    // MARK: - Persist config

    private struct HelperConfig: Codable {
        var blockingEnabled: Bool
        var upstreamDNS: [String]
    }

    private func saveConfig() {
        let config = HelperConfig(blockingEnabled: proxy.isBlockingEnabled, upstreamDNS: proxy.upstreamServers)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: URL(fileURLWithPath: configFilePath))
        }
    }

    enum Err: Error {
        case socketCreationFailed
        case bindFailed(Int32)
        case listenFailed
    }
}
