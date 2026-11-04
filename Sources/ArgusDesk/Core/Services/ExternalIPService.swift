import Darwin
import Foundation

/// Looks up this Mac's public IP address from a public web service.
///
/// This is the only place the local section contacts the internet. It is
/// optional (see the "Show external IP" setting), runs at most every ten
/// minutes, and sends no identifying information beyond a normal HTTPS request.
/// The reply is accepted only if it is a valid IP address, so unexpected text
/// from the service can never be shown in the window.
@MainActor
final class ExternalIPService {
    /// Public service that answers with the caller's address as plain text.
    static let endpoint = URL(string: "https://api.ipify.org")!

    /// How long a successful answer is reused before asking again.
    static let successInterval: TimeInterval = 600

    /// How long to wait before retrying after a failure.
    static let retryInterval: TimeInterval = 60

    /// Most recent valid address, kept while a refresh is running or failing.
    private(set) var address: String?

    /// True when the latest attempt failed and no earlier address is known.
    private var failed = false

    /// Earliest time another request may be made.
    private var nextAttempt = Date.distantPast

    /// Prevents overlapping requests.
    private var requestInFlight = false

    /// Session with short timeouts and no cache or cookies.
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 10
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Text for the dashboard: the address, `…` while pending, `n/a` after a
    /// failure with nothing to show, or nil when the lookup is turned off.
    func display(enabled: Bool) -> String? {
        guard enabled else {
            return nil
        }

        return address ?? (failed ? "n/a" : "…")
    }

    /// Starts a request if the lookup is enabled and the cached value is stale.
    /// Turning the lookup off forgets the address and stops all requests.
    func refreshIfDue(enabled: Bool, now: Date = Date()) {
        guard enabled else {
            address = nil
            failed = false
            nextAttempt = .distantPast
            return
        }

        guard !requestInFlight, now >= nextAttempt else {
            return
        }

        requestInFlight = true
        Task {
            let result = await Self.fetch(using: session)
            requestInFlight = false
            if let result {
                address = result
                failed = false
                nextAttempt = Date().addingTimeInterval(Self.successInterval)
            } else {
                failed = address == nil
                nextAttempt = Date().addingTimeInterval(Self.retryInterval)
            }
        }
    }

    /// Performs the HTTPS request and validates the reply.
    private nonisolated static func fetch(using session: URLSession) async -> String? {
        guard
            let (data, response) = try? await session.data(from: endpoint),
            (response as? HTTPURLResponse)?.statusCode == 200
        else {
            return nil
        }

        return parseAddress(data)
    }

    /// Returns the reply as an address only if it is a valid IPv4 or IPv6 literal.
    nonisolated static func parseAddress(_ data: Data) -> String? {
        guard
            data.count <= 64,
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }

        var v4 = in_addr()
        var v6 = in6_addr()
        let valid = inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
        return valid ? text : nil
    }
}
