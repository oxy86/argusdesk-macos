import Foundation

/// Monotonic per-connection scheduling. A slow server never blocks another
/// server's refresh, and missed deadlines never cause catch-up request bursts.
struct ServerRefreshSchedule {
    private var due: [String: TimeInterval] = [:]
    private var active: Set<String> = []

    mutating func begin(_ server: ServerConfig, now: TimeInterval, global: Int, force: Bool = false) -> Bool {
        let key = server.connectionID
        guard !active.contains(key), force || now >= (due[key] ?? 0) else { return false }
        active.insert(key)
        due[key] = now + Double(server.effectiveRefreshSeconds(global: global))
        return true
    }

    mutating func finish(_ server: ServerConfig, now: TimeInterval) {
        let key = server.connectionID
        active.remove(key)
        // If a check ran past its deadline, leave a small pause before retrying.
        due[key] = max(due[key] ?? now, now + 1)
    }

    mutating func resetDeadlines() { due.removeAll() }
    var isRefreshing: Bool { !active.isEmpty }
}
