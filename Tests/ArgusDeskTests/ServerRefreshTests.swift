import Foundation
import XCTest
@testable import ArgusDesk

/// Uses simulated monotonic time so scheduling coverage needs no real sleeps.
final class ServerRefreshTests: XCTestCase {
    private func server(seconds: Int? = nil, host: String = "example.com") -> ServerConfig {
        ServerConfig(name: "legacy", host: host, sshUser: "username", sshPort: 22,
                     httpURL: nil, httpUserAgent: nil, enabledChecks: ["ssh"], refreshSeconds: seconds)
    }

    func testIndependentDeadlinesAndNoOverlap() {
        let fast = server(seconds: 10)
        let slow = server(seconds: 60, host: "other.example.com")
        var schedule = ServerRefreshSchedule()
        XCTAssertTrue(schedule.begin(fast, now: 0, global: 30))
        XCTAssertTrue(schedule.begin(slow, now: 0, global: 30))
        XCTAssertFalse(schedule.begin(fast, now: 20, global: 30, force: true))
        schedule.finish(fast, now: 3)
        XCTAssertFalse(schedule.begin(fast, now: 9, global: 30))
        XCTAssertTrue(schedule.begin(fast, now: 10, global: 30))
        XCTAssertFalse(schedule.begin(slow, now: 10, global: 30))
    }

    func testGlobalFallbackAndNoCatchUpBurst() {
        let config = server()
        XCTAssertEqual(config.effectiveRefreshSeconds(global: 45), 45)
        var schedule = ServerRefreshSchedule()
        XCTAssertTrue(schedule.begin(config, now: 0, global: 10))
        schedule.finish(config, now: 20)
        XCTAssertFalse(schedule.begin(config, now: 20, global: 10))
        XCTAssertTrue(schedule.begin(config, now: 21, global: 10))
        schedule.resetDeadlines()
        XCTAssertFalse(schedule.begin(config, now: 22, global: 10)) // still active
    }

    func testOptionalIntervalAndFriendlyLabelDecoding() throws {
        for field in ["", ",\"refresh_seconds\":null", ",\"refresh_seconds\":\"\"", ",\"refresh_seconds\":\"  \""] {
            let json = "{\"host\":\"example.com\",\"name\":\"legacy\"\(field)}"
            let decoded = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
            XCTAssertNil(decoded.refreshSeconds)
            XCTAssertEqual(decoded.displayName, "example.com")
        }
        let labeled = try JSONDecoder().decode(ServerConfig.self, from: Data("{\"host\":\"example.com\",\"label\":\" friendly \",\"refresh_seconds\":15}".utf8))
        XCTAssertEqual(labeled.displayName, "friendly")
        XCTAssertEqual(labeled.refreshSeconds, 15)
        XCTAssertEqual(labeled.connectionID, server().connectionID)
        for field in ["0", "-1", "1.5", "\"invalid\""] {
            XCTAssertThrowsError(try JSONDecoder().decode(ServerConfig.self, from: Data("{\"host\":\"example.com\",\"refresh_seconds\":\(field)}".utf8)))
        }
    }

    func testLocalLabelAndHostnameFallback() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{\"local_label\":\"My Mac\"}".utf8))
        XCTAssertEqual(config.localLabel, "My Mac")
        let monitor = LocalMonitor()
        XCTAssertEqual(monitor.snapshot(label: " My Mac ").hostname, "My Mac")
        XCTAssertEqual(monitor.snapshot(label: " ").hostname, monitor.snapshot().hostname)
    }

    func testSavingBlankIntervalPreservesOtherFields() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("servers.json")
        try Data("{\"custom\":123,\"servers\":[{\"host\":\"example.com\",\"label\":\"friendly\",\"refresh_seconds\":15,\"extra\":true}]}".utf8).write(to: file)
        XCTAssertNil(ConfigSaver.saveRefreshIntervals(to: file, values: [server().connectionID: ""], localLabel: "My Mac"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(object["custom"] as? Int, 123)
        XCTAssertEqual(object["local_label"] as? String, "My Mac")
        let entries = try XCTUnwrap(object["servers"] as? [[String: Any]])
        XCTAssertNil(entries[0]["refresh_seconds"])
        XCTAssertEqual(entries[0]["label"] as? String, "friendly")
        XCTAssertEqual(entries[0]["extra"] as? Bool, true)
        XCTAssertNotNil(ConfigSaver.saveRefreshIntervals(to: file, values: [server().connectionID: "-1"]))
    }
}
