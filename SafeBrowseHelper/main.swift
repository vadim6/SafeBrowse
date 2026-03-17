import Foundation
import Network

// MARK: - Setup data directory

try FileManager.default.createDirectory(
    atPath: dataDir,
    withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o755]
)

// Create empty allowlist if it doesn't exist
if !FileManager.default.fileExists(atPath: allowlistFilePath) {
    FileManager.default.createFile(atPath: allowlistFilePath, contents: Data(), attributes: nil)
}

// MARK: - Initialise components

let store = BlocklistStore()
store.load(blocklistPath: blocklistFilePath, allowlistPath: allowlistFilePath)

let sysDNS = SystemDNS(dataDir: dataDir)
let proxy = DNSProxy(store: store)

// MARK: - Restore state from previous session

struct PersistedConfig: Codable {
    var blockingEnabled: Bool = true
    var upstreamDNS: [String] = ["1.1.1.1", "8.8.8.8"]
}

var config = PersistedConfig()
if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)),
   let saved = try? JSONDecoder().decode(PersistedConfig.self, from: data) {
    config = saved
}

proxy.setBlocking(config.blockingEnabled)
proxy.setUpstreamServers(config.upstreamDNS)
// Always point system DNS at 127.0.0.1 — the proxy runs regardless of blocking state.
// Blocking disabled = proxy forwards without filtering; DNS still routes through it.
sysDNS.enableLocalDNS()

let startBlocking = config.blockingEnabled

// MARK: - Start DNS proxy

do {
    try proxy.start()
} catch {
    NSLog("[main] FATAL: Could not start DNS proxy: %@", error.localizedDescription)
    NSLog("[main] Make sure the helper is running as root (port 53 requires root).")
    exit(1)
}

// MARK: - Start control socket

let server = SocketServer(
    path: socketPath,
    proxy: proxy,
    store: store,
    sysDNS: sysDNS,
    blocklistPath: blocklistFilePath,
    allowlistPath: allowlistFilePath
)

do {
    try server.start()
} catch {
    NSLog("[main] FATAL: Could not start socket server: %@", error.localizedDescription)
    exit(1)
}

// MARK: - Schedule midnight stats reset

func scheduleMidnightReset() {
    let cal = Calendar.current
    guard let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) else { return }
    let midnight = cal.startOfDay(for: tomorrow)
    let delay = midnight.timeIntervalSinceNow

    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
        proxy.resetDailyStats()
        // Reschedule for next midnight
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
            proxy.resetDailyStats()
        }
        RunLoop.current.run()
    }
}
scheduleMidnightReset()

// MARK: - Re-apply DNS on network changes
// macOS resets DNS to DHCP values when the network changes (new WiFi, VPN, DHCP renewal).
// Watch for path updates and re-apply 127.0.0.1 whenever blocking is on.

let networkMonitor = NWPathMonitor()
networkMonitor.pathUpdateHandler = { path in
    guard proxy.isBlockingEnabled, path.status == .satisfied else { return }
    // Small delay: let the OS finish configuring the new interface before we override DNS.
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
        NSLog("[main] Network change detected — re-applying local DNS")
        sysDNS.enableLocalDNS()
    }
}
networkMonitor.start(queue: DispatchQueue.global(qos: .utility))

// MARK: - Signal handlers (all use only async-signal-safe primitives)

// Ignore SIGPIPE globally. Without this, any write() to a socket/pipe whose
// read-end is closed (e.g. app timed out and closed its connection before the
// helper sent the response) terminates the process instantly with no output.
// With SIG_IGN, send() returns EPIPE which the caller can handle or ignore.
signal(SIGPIPE, SIG_IGN)

signal(SIGTERM) { _ in
    // Only async-signal-safe calls here.
    // NSLog and subprocess calls (restoreSystemDNS) are NOT async-signal-safe and can deadlock.
    // DNS restoration is handled by uninstall.sh via the socket command before the daemon unloads.
    let msg: StaticString = "[main] SIGTERM received — exiting\n"
    msg.withUTF8Buffer { buf in _ = write(STDERR_FILENO, buf.baseAddress, buf.count) }
    exit(0)
}

signal(SIGHUP) { _ in
    let msg: StaticString = "[main] SIGHUP received — exiting\n"
    msg.withUTF8Buffer { buf in _ = write(STDERR_FILENO, buf.baseAddress, buf.count) }
    exit(0)
}

// Log fatal crash signals before re-raising so the OS can write a crash report.
func installCrashHandler(for sig: Int32) {
    signal(sig) { receivedSig in
        // StaticString lives in the binary's data segment — zero allocation, truly async-signal-safe.
        // (String interpolation would call malloc which can deadlock if the crash happened inside malloc.)
        let msg: StaticString = "[main] FATAL signal — helper crashed. Check DiagnosticReports.\n"
        msg.withUTF8Buffer { buf in _ = write(STDERR_FILENO, buf.baseAddress, buf.count) }
        signal(receivedSig, SIG_DFL)   // restore default so OS writes a proper crash report
        raise(receivedSig)
    }
}

installCrashHandler(for: SIGSEGV)
installCrashHandler(for: SIGABRT)
installCrashHandler(for: SIGBUS)
installCrashHandler(for: SIGILL)
installCrashHandler(for: SIGFPE)

NSLog("[main] safebrowse-helper ready (blocking: %@)", startBlocking ? "yes" : "no")
RunLoop.main.run()
