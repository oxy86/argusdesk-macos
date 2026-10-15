import XCTest
@testable import ArgusDesk

final class GPUThresholdTests: XCTestCase {
    func testGPUUtilizationAndVRAMHaveIndependentLimits() {
        let thresholds = Thresholds(gpuWarningPercent: 70, gpuErrorPercent: 90,
                                    gpuMemoryWarningPercent: 80, gpuMemoryErrorPercent: 95)
        let raw = Metric(label: "gpu0", value: "10% · 15GiB / 16GiB", severity: .ok,
                         gpuUtilizationPercent: 10, gpuMemoryUsagePercent: 96)
        let metrics = SeverityEngine(thresholds: thresholds).evaluate(metrics: [raw])
        XCTAssertEqual(metrics[0].severity, .error)
        XCTAssertEqual(metrics[0].gpuMemoryUsagePercent, 96)
        var alerts = MetricAlerts()
        let alert = alerts.evaluate(servers: [ServerStatus(name: "compute", severity: .error, headline: "", metrics: metrics)],
                                    thresholds: thresholds, recovery: true)
        XCTAssertTrue(alert[0].body.contains("95% VRAM"))
        XCTAssertFalse(alert[0].body.contains("90% GPU"))
        let highCompute = Metric(label: "gpu0", value: "75%", severity: .ok, gpuUtilizationPercent: 75, gpuMemoryUsagePercent: 5)
        XCTAssertEqual(SeverityEngine(thresholds: thresholds).evaluate(metrics: [highCompute])[0].severity, .warning)
    }

    func testMissingUtilizationIsNotParsedFromVRAMText() {
        let raw = NVIDIAMetrics().parse("gpu_csv=0, GPU-example, N/A, 100, 1000")
        XCTAssertNil(raw[0].gpuUtilizationPercent)
        XCTAssertEqual(raw[0].gpuMemoryUsagePercent, 10)
        XCTAssertEqual(SeverityEngine(thresholds: .default).evaluate(metrics: raw)[0].severity, .ok)
    }
}
