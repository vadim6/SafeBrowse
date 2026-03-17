import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Sends commands to safebrowse-helper over a Unix domain socket.
/// Each call opens a fresh connection (fire-and-forget style).
final class HelperClient {

    func send(_ command: Command, payload: String? = nil, reply: ((Response) -> Void)?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let response = self.sendSync(CommandMessage(command: command, payload: payload))
            if let reply {
                reply(response ?? .error("No response from helper"))
            }
        }
    }

    // MARK: - Synchronous send / receive

    private func sendSync(_ message: CommandMessage) -> Response? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            socketPath.withCString { src in
                let len = min(strlen(src) + 1, dst.count)
                dst.copyBytes(from: UnsafeRawBufferPointer(start: src, count: len))
            }
        }

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        guard let data = try? JSONEncoder().encode(message) else { return nil }
        _ = data.withUnsafeBytes { ptr in
            Foundation.send(fd, ptr.baseAddress!, ptr.count, 0)
        }

        var buf = [UInt8](repeating: 0, count: 4096)
        let n = recv(fd, &buf, buf.count - 1, 0)
        guard n > 0 else { return nil }

        return try? JSONDecoder().decode(Response.self, from: Data(buf[0 ..< n]))
    }
}
