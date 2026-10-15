import XCTest
@testable import ArgusDesk

/// Regression checks for driver variation, disabled checks, and mixed-role cards.
final class MonitoringPresentationTests: XCTestCase {
    func testNVIDIAProcessMemoryDoesNotImplyUtilization() {
        let metrics = NVIDIAMetrics().parse("""
        gpu_csv=0, GPU-example, 0, 12590, 16376
        gpu_process_status=0
        gpu_process_csv=GPU-example, 123, /opt/models/venv/bin/python, 12272
        gpu_pmon=# gpu pid type sm mem enc dec jpg ofa fb ccpm command
        gpu_pmon=0 123 C - - - - - - 12272 0 python
        gpu_pmon=0 45 G - - - - - - 171 0 Xorg
        """)
        XCTAssertEqual(metrics.count, 3)
        XCTAssertTrue(metrics[0].value.hasPrefix("0%"))
        let python = metrics.first { $0.label == "pid 123" }
        XCTAssertTrue(python?.value.contains("python · 11.98GiB · SM n/a") == true)
        XCTAssertEqual(metrics.filter { $0.label == "pid 123" }.count, 1)
        XCTAssertTrue(metrics.contains { $0.value.contains("Xorg") })
    }

    func testMultipleGPUsAndVariablePmonColumns() {
        let metrics = NVIDIAMetrics().parse("""
        gpu_csv=0, GPU-a, 5, 100, 1000
        gpu_csv=1, GPU-b, 80, 200, 2000
        gpu_process_csv=GPU-b, 987, /opt/runner, 200
        gpu_pmon=# gpu pid type sm mem enc dec fb command
        gpu_pmon=1 987 C 72 15 0 0 200 runner
        """)
        XCTAssertEqual(metrics.count, 3)
        XCTAssertTrue(metrics.last?.value.contains("SM 72% (gpu1)") == true)
    }

    func testUnavailableDriverAndEmptyProcessInventory() {
        XCTAssertEqual(NVIDIAMetrics().parse("").first?.value, "n/a")
        let idle = NVIDIAMetrics().parse("gpu_csv=0, GPU-a, 0, 0, 8192\ngpu_process_status=0")
        XCTAssertEqual(idle.last?.value, "none")
        let unavailable = NVIDIAMetrics().parse("gpu_csv=0, GPU-a, 0, 0, 8192")
        XCTAssertEqual(unavailable.last?.value, "n/a")
    }

    func testDisabledChecksRemainNeutralAndAreHiddenFromBody() {
        let config = ServerConfig(name: "compute", host: "example.com", sshUser: "username",
                                  sshPort: 22, httpURL: nil, httpUserAgent: nil,
                                  enabledChecks: ["ssh", "load", "disk", "memory", "gpu"])
        let pending = ServerStatus.pending(from: config)
        XCTAssertEqual(pending.metrics.first { $0.label == "ping" }?.value, "off")
        XCTAssertEqual(Set(pending.visibleMetrics.map(\.label)), Set(["load", "disk /", "mem", "gpu"]))
        let engine = SeverityEngine(thresholds: .default)
        let off = engine.evaluate(metrics: [Metric(label: "ping", value: "off", severity: .unknown)])
        XCTAssertEqual(off[0].severity, .unknown)
        XCTAssertEqual(engine.serverSeverity(for: off), .unknown)
    }

    func testFourServerLayoutsGrowWithGPUProcessInventory() {
        let metric = Metric(label: "load", value: "0.1", severity: .ok)
        let ordinary = ServerStatus(name: "example", severity: .ok, headline: "", metrics: [metric])
        var servers = Array(repeating: ordinary, count: 4)
        XCTAssertEqual(ServerLayout.horizontal.contentSize(servers: servers).width, 1518)
        XCTAssertEqual(ServerLayout.vertical.contentSize(servers: servers).height, 820)
        let processes = (1...30).map { Metric(label: "pid \($0)", value: "runner", severity: .ok) }
        servers[3] = ServerStatus(name: "compute", severity: .ok, headline: "", metrics: [metric] + processes)
        XCTAssertGreaterThan(ServerLayout.vertical.contentSize(servers: servers).height, 820)
        XCTAssertGreaterThan(ServerLayout.horizontal.contentSize(servers: servers).height, 420)
    }
}
