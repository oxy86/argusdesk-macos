import XCTest
@testable import ArgusDesk

/// Menu summaries must account for unchecked servers and independent results.
final class MenuSummaryTests: XCTestCase {
    @MainActor
    func testMenuOnlyPublishesServerChangesNotLocalSamples() {
        let menu = MenuSnapshot()
        let server = ServerStatus(name: "web", severity: .ok, headline: "", metrics: [])
        let first = DashboardViewModel.empty.updating(servers: [server], lastRefresh: "10:00")
        var publications = 0
        let observation = menu.$dashboard.sink { _ in publications += 1 }
        menu.update(from: first)
        let afterServerResult = publications
        let local = LocalStatus(hostname: "Mac", osVersion: "macOS", uptime: "1d",
            battery: "90%", cpu: "35%", memory: "40%", disk: "50%", network: "Wi-Fi")
        menu.update(from: first.updating(local: local))
        menu.update(from: first)
        XCTAssertEqual(publications, afterServerResult)
        // Independent completions can arrive within the same displayed minute.
        let next = ServerStatus(name: "web", severity: .warning, headline: "", metrics: [])
        menu.update(from: first.updating(servers: [next], lastRefresh: "10:00"))
        XCTAssertEqual(publications, afterServerResult + 1)
        XCTAssertEqual(menu.dashboard.servers.first?.severity, .warning)
        withExtendedLifetime(observation) {}
    }

    func testPendingServerPreventsAllHealthySummary() {
        let ok = ServerStatus(name: "healthy", severity: .ok, headline: "", metrics: [])
        let pending = ServerStatus(name: "pending", severity: .unknown, headline: "", metrics: [])
        let dashboard = DashboardViewModel.empty.updating(servers: [ok, pending], lastRefresh: "10:00")
        XCTAssertEqual(dashboard.overallSeverity, .unknown)
        XCTAssertEqual(dashboard.menuServers.map(\.name), ["pending", "healthy"])
        XCTAssertEqual(dashboard.severityCounts.ok, 1)
        XCTAssertNil(dashboard.menuServers.first?.lastResultAt)
    }

    func testEveryServerIsIncludedAndFailureKeepsItsActualCheckValues() {
        let resultAt = Date(timeIntervalSince1970: 100)
        let failed = ServerStatus(name: "compute", severity: .error, headline: "fail ERR",
            metrics: [Metric(label: "ssh", value: "timeout", severity: .error),
                      Metric(label: "ping", value: "off", severity: .unknown),
                      Metric(label: "mem", value: "n/a", severity: .unknown)],
            refreshInterval: "30s", lastResultAt: resultAt)
        let ok = ServerStatus(name: "web", severity: .ok, headline: "", metrics: [])
        let dashboard = DashboardViewModel.empty.updating(servers: [ok, failed], lastRefresh: "10:00")
        XCTAssertEqual(dashboard.overallSeverity, .error)
        XCTAssertEqual(dashboard.menuServers.map(\.name), ["compute", "web"])
        XCTAssertEqual(failed.menuMetrics.map(\.value), ["timeout", "n/a"])
        XCTAssertEqual(dashboard.menuServers.first?.lastResultAt, resultAt)
    }

    func testConfigurationReloadDoesNotReusePreviousResultsTime() {
        let old = DashboardViewModel.empty.updating(servers: [], lastRefresh: "10:00")
        let replaced = old.replacing(config: AppConfig(), servers: [], validation: nil)
        XCTAssertEqual(replaced.lastRefresh, "not refreshed")
        XCTAssertEqual(replaced.overallSeverity, .unknown)
        let pending = DashboardViewModel.pending(config: AppConfig(),
            configSource: URL(fileURLWithPath: "/tmp/example.json"), validation: nil)
        XCTAssertEqual(pending.lastRefresh, "not refreshed")
    }
}
