import XCTest
@testable import ArgusDesk

/// Covers the collapsed LOCAL summary, GPU/load readings, and the public IP lookup.
final class LocalStatusTests: XCTestCase {
    func testAddressSummaryJoinsAddressesAndOSVersion() {
        var status = DashboardViewModel.empty.local
        XCTAssertEqual(status.addressSummary, "- · macOS")

        status.internalIP = "192.0.2.10"
        status.externalIP = "203.0.113.7"
        XCTAssertEqual(status.addressSummary, "192.0.2.10 · 203.0.113.7 · macOS")

        // Turning the lookup off removes the external address entirely.
        status.externalIP = nil
        XCTAssertEqual(status.addressSummary, "192.0.2.10 · macOS")
    }

    func testShortLoadUsesOneMinuteAverage() {
        var status = DashboardViewModel.empty.local
        status.loadAverage = "3.92 3.54 3.50"
        XCTAssertEqual(status.shortLoad, "3.92")
        status.loadAverage = "n/a"
        XCTAssertEqual(status.shortLoad, "n/a")
    }

    func testLoadAverageFormatting() {
        XCTAssertEqual(LocalMonitor.formatLoadAverage([3.921, 3.5, 0]), "3.92 3.50 0.00")
    }

    func testGPUUtilizationParsingIsClamped() {
        XCTAssertEqual(LocalMonitor.gpuUtilization(from: ["Device Utilization %": 20]), 20)
        XCTAssertEqual(LocalMonitor.gpuUtilization(from: ["Device Utilization %": 250]), 100)
        XCTAssertNil(LocalMonitor.gpuUtilization(from: ["Renderer Utilization %": 5]))
        XCTAssertNil(LocalMonitor.gpuUtilization(from: [:]))
    }

    func testLiveSnapshotHasLoadAndGPUValues() {
        let status = LocalMonitor().snapshot()
        XCTAssertEqual(status.loadAverage.split(separator: " ").count, 3)
        XCTAssertFalse(status.gpu.isEmpty)
        XCTAssertFalse(status.internalIP.isEmpty)
    }

    func testExternalIPReplyMustBeAnAddress() {
        XCTAssertEqual(ExternalIPService.parseAddress(Data("203.0.113.7\n".utf8)), "203.0.113.7")
        XCTAssertEqual(ExternalIPService.parseAddress(Data("2001:db8::1".utf8)), "2001:db8::1")
        XCTAssertNil(ExternalIPService.parseAddress(Data("<html>blocked</html>".utf8)))
        XCTAssertNil(ExternalIPService.parseAddress(Data("999.1.1.1".utf8)))
        XCTAssertNil(ExternalIPService.parseAddress(Data()))
        XCTAssertNil(ExternalIPService.parseAddress(Data(repeating: 49, count: 200)))
    }

    @MainActor
    func testExternalIPDisplayStates() {
        let service = ExternalIPService()
        XCTAssertNil(service.display(enabled: false))
        XCTAssertEqual(service.display(enabled: true), "…")
        // A disabled lookup never starts a request and stays pending-free.
        service.refreshIfDue(enabled: false)
        XCTAssertNil(service.address)
    }
}
