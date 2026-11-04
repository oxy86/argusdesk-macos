import XCTest
@testable import ArgusDesk

/// Covers the collapsed-row chips and the open/closed rules for server rows.
final class ServerChipTests: XCTestCase {
    private func server(_ metrics: [Metric], severity: Severity = .ok) -> ServerStatus {
        ServerStatus(name: "example", severity: severity, headline: "", metrics: metrics)
    }

    private func metric(_ label: String, _ severity: Severity, _ value: String = "x") -> Metric {
        Metric(label: label, value: value, severity: severity)
    }

    func testHealthyServerHasNoChips() {
        let status = server([metric("ssh", .ok), metric("load", .ok), metric("nginx", .ok), metric("swap", .unknown)])
        XCTAssertTrue(status.chips.isEmpty)
    }

    func testWarningAndErrorBecomeChipsWithErrorsFirst() {
        let status = server([
            metric("ssh", .ok), metric("php-fpm", .warning), metric("disk /", .error), metric("nginx", .ok)
        ])
        XCTAssertEqual(status.chips, [
            ServerChip(label: "disk", severity: .error),
            ServerChip(label: "php-fpm", severity: .warning)
        ])
    }

    func testPingHTTPAndDisabledChecksNeverBecomeChips() {
        let status = server([
            metric("ssh", .ok), metric("ping", .error), metric("http", .warning),
            metric("nginx", .error, "off"), metric("db", .unknown)
        ])
        XCTAssertTrue(status.chips.isEmpty)
    }

    func testSSHFailureReplacesEverythingWithUnreachable() {
        let status = server([metric("ssh", .error), metric("load", .error), metric("mem", .warning)])
        XCTAssertEqual(status.chips, [ServerChip(label: "unreachable", severity: .error)])
    }

    func testExtraChipsAreCountedNotDrawn() {
        let status = server([
            metric("load", .warning), metric("disk /", .warning), metric("mem", .warning),
            metric("nginx", .warning), metric("db", .error)
        ])
        let summary = status.chipSummary
        XCTAssertEqual(summary.visible.map(\.label), ["db", "load", "disk"])
        XCTAssertEqual(summary.hidden, 2)
    }

    func testRowsOpenOnProblemsUnlessUserOverrides() {
        XCTAssertFalse(ServerExpansion.isExpanded(severity: .ok, override: nil))
        XCTAssertFalse(ServerExpansion.isExpanded(severity: .unknown, override: nil))
        XCTAssertTrue(ServerExpansion.isExpanded(severity: .warning, override: nil))
        XCTAssertTrue(ServerExpansion.isExpanded(severity: .error, override: nil))
        XCTAssertFalse(ServerExpansion.isExpanded(severity: .error, override: false))
        XCTAssertTrue(ServerExpansion.isExpanded(severity: .ok, override: true))
    }

    func testClosedRowStaysClosedUntilServerRecovers() {
        var overrides = ["web": false, "db": true, "gone": true]
        // Still failing: the user's choice is kept. Healthy or removed: forgotten.
        overrides = ServerExpansion.pruned(overrides: overrides, severities: ["web": .error, "db": .ok])
        XCTAssertEqual(overrides, ["web": false])
        overrides = ServerExpansion.pruned(overrides: overrides, severities: ["web": .ok])
        XCTAssertTrue(overrides.isEmpty)
        // The next failure opens the row again.
        XCTAssertTrue(ServerExpansion.isExpanded(severity: .error, override: overrides["web"]))
    }
}
