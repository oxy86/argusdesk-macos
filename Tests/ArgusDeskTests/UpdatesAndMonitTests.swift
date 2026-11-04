import XCTest
@testable import ArgusDesk

/// Covers the pending-updates and Monit checks: parsing, severity, and which
/// checks reach the remote command.
final class UpdatesAndMonitTests: XCTestCase {
    private let engine = SeverityEngine(thresholds: .default)

    private func severity(_ label: String, _ value: String) -> Severity {
        engine.evaluate(metrics: [Metric(label: label, value: value, severity: .ok)])[0].severity
    }

    func testUpdateCountsAreFormattedWithSecuritySeparate() {
        XCTAssertEqual(RemoteMonitor.formatUpdates("0 0"), "up to date")
        XCTAssertEqual(RemoteMonitor.formatUpdates("0 4"), "0 security · 4 other")
        XCTAssertEqual(RemoteMonitor.formatUpdates("18 49"), "18 security · 49 other")
        XCTAssertNil(RemoteMonitor.formatUpdates("n/a"))
        XCTAssertNil(RemoteMonitor.formatUpdates("1"))
        XCTAssertNil(RemoteMonitor.formatUpdates("-1 3"))
        XCTAssertNil(RemoteMonitor.formatUpdates("a b"))
    }

    func testUpdatesWarnForSecurityOrTenOrMoreAndNeverError() {
        XCTAssertEqual(severity("updates", "up to date"), .ok)
        XCTAssertEqual(severity("updates", "0 security · 4 other"), .ok)
        XCTAssertEqual(severity("updates", "0 security · 9 other"), .ok)
        XCTAssertEqual(severity("updates", "0 security · 10 other"), .warning)
        XCTAssertEqual(severity("updates", "1 security · 0 other"), .warning)
        XCTAssertEqual(severity("updates", "18 security · 49 other"), .warning)
        XCTAssertEqual(severity("updates", "n/a"), .unknown)
        XCTAssertEqual(severity("updates", "pending"), .unknown)
    }

    func testMonitIsOkOnlyWhenEveryServiceIsOk() {
        XCTAssertEqual(severity("monit", "19/19"), .ok)
        XCTAssertEqual(severity("monit", "18/19"), .error)
        XCTAssertEqual(severity("monit", "0/19"), .error)
        XCTAssertEqual(severity("monit", "0/0"), .unknown)
        XCTAssertEqual(severity("monit", "n/a"), .unknown)
        XCTAssertEqual(severity("monit", "pending"), .unknown)
    }

    func testRemoteCommandOnlyRunsEnabledChecks() {
        let none = RemoteMonitor.remoteCommand(enabledChecks: ["load"])
        XCTAssertTrue(none.contains("if [ \"0\" = \"1\" ]; then\n  # Simulated upgrade"))
        XCTAssertTrue(none.contains("if [ \"0\" = \"1\" ]; then\n  # Needs passwordless sudo"))

        let both = RemoteMonitor.remoteCommand(enabledChecks: ["updates", "monit"])
        XCTAssertTrue(both.contains("if [ \"1\" = \"1\" ]; then\n  # Simulated upgrade"))
        XCTAssertTrue(both.contains("if [ \"1\" = \"1\" ]; then\n  # Needs passwordless sudo"))
        // Only the read-only simulation and the single named sudo command appear.
        XCTAssertTrue(both.contains("apt-get -s upgrade"))
        XCTAssertTrue(both.contains("sudo -n monit summary"))
        XCTAssertFalse(both.contains("apt-get upgrade"))
    }

    func testNewChecksAreKnownAndShownInPendingServer() {
        XCTAssertTrue(knownCheckKeys.isSuperset(of: ["updates", "monit"]))
        let config = ServerConfig(name: "example", host: "example.com", sshUser: "username",
                                  sshPort: 22, httpURL: nil, httpUserAgent: nil,
                                  enabledChecks: ["ssh", "updates"])
        let pending = ServerStatus.pending(from: config)
        XCTAssertEqual(pending.metrics.first { $0.label == "updates" }?.value, "pending")
        XCTAssertEqual(pending.metrics.first { $0.label == "monit" }?.value, "off")
        XCTAssertEqual(Set(pending.visibleMetrics.map(\.label)), ["updates"])
    }

    func testUnhealthyNewChecksBecomeChips() {
        let metrics = engine.evaluate(metrics: [
            Metric(label: "ssh", value: "ok", severity: .ok),
            Metric(label: "updates", value: "1 security · 0 other", severity: .ok),
            Metric(label: "monit", value: "18/19", severity: .ok)
        ])
        let status = ServerStatus(name: "example", severity: engine.serverSeverity(for: metrics), headline: "", metrics: metrics)
        XCTAssertEqual(status.severity, .error)
        XCTAssertEqual(status.chips.map(\.label), ["monit", "updates"])
    }
}
