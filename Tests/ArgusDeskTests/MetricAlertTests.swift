import XCTest
@testable import ArgusDesk

/// Threshold transitions are tested without posting real desktop notifications.
final class MetricAlertTests: XCTestCase {
    private func server(_ metrics: [Metric]) -> [ServerStatus] {
        [ServerStatus(name: "example.com", severity: .error, headline: "", metrics: metrics)]
    }

    func testSeparateMetricsAlertEvenWhenServerAlreadyHasAFault() {
        var tracker = MetricAlerts()
        let disk = Metric(label: "disk /", value: "85%", severity: .warning)
        let first = tracker.evaluate(servers: server([disk]), thresholds: .default, recovery: true)
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(first[0].body.contains("80%"))
        XCTAssertTrue(tracker.evaluate(servers: server([disk]), thresholds: .default, recovery: true).isEmpty)
        let memory = Metric(label: "mem", value: "95%", severity: .error)
        let next = tracker.evaluate(servers: server([disk, memory]), thresholds: .default, recovery: true)
        XCTAssertEqual(next.count, 1)
        XCTAssertTrue(next[0].title.contains("Memory critical"))
        XCTAssertTrue(next[0].body.contains("90%"))
    }

    func testUnknownDoesNotCauseFalseRecoveryOrRepeatedAlert() {
        var tracker = MetricAlerts()
        let bad = Metric(label: "mem", value: "85%", severity: .warning)
        _ = tracker.evaluate(servers: server([bad]), thresholds: .default, recovery: true)
        let unknown = Metric(label: "mem", value: "-", severity: .unknown)
        XCTAssertTrue(tracker.evaluate(servers: server([unknown]), thresholds: .default, recovery: true).isEmpty)
        XCTAssertTrue(tracker.evaluate(servers: server([bad]), thresholds: .default, recovery: true).isEmpty)
        let good = Metric(label: "mem", value: "50%", severity: .ok)
        XCTAssertEqual(tracker.evaluate(servers: server([good]), thresholds: .default, recovery: true).count, 1)
        XCTAssertTrue(tracker.evaluate(servers: server([good]), thresholds: .default, recovery: true).isEmpty)
    }

    func testEscalationRecoveryPreferenceAndDisabledChecks() {
        var tracker = MetricAlerts()
        let warning = Metric(label: "ping", value: "250ms", severity: .warning)
        _ = tracker.evaluate(servers: server([warning]), thresholds: .default, recovery: false)
        let error = Metric(label: "ping", value: "1500ms", severity: .error)
        XCTAssertEqual(tracker.evaluate(servers: server([error]), thresholds: .default, recovery: false).count, 1)
        let good = Metric(label: "ping", value: "5ms", severity: .ok)
        XCTAssertTrue(tracker.evaluate(servers: server([good]), thresholds: .default, recovery: false).isEmpty)
        let off = Metric(label: "ping", value: "off", severity: .unknown)
        XCTAssertTrue(tracker.evaluate(servers: server([off]), thresholds: .default, recovery: true).isEmpty)
    }
}
