import XCTest
@testable import ArgusDesk

/// Covers per-server systemd unit names (`service_units` in servers.json).
final class ServiceUnitTests: XCTestCase {
    /// Without an override the default unit name is used, as before.
    func testDefaultUnitIsUsedWithoutOverride() {
        let command = RemoteMonitor.remoteCommand(enabledChecks: ["memcached"])
        XCTAssertTrue(command.contains("svc_metric memcached memcached\n") || command.contains("svc_metric memcached memcached"))
        XCTAssertFalse(command.contains("memcached-socket"))
    }

    /// A configured unit replaces the default and is single-quoted.
    func testOverrideReplacesDefaultUnit() {
        let command = RemoteMonitor.remoteCommand(enabledChecks: ["memcached", "nginx"],
                                                  serviceUnits: ["memcached": "memcached-socket"])
        XCTAssertTrue(command.contains("svc_metric memcached 'memcached-socket'"))
        XCTAssertTrue(command.contains("svc_metric nginx nginx"))
    }

    /// Unsafe names never reach the remote shell; the default is used instead.
    func testUnsafeUnitNamesAreRejected() {
        for bad in ["x; rm -rf /", "a b", "$(id)", "a'b", "", "a\nb"] {
            XCTAssertFalse(isValidServiceUnitName(bad), bad)
            let command = RemoteMonitor.remoteCommand(enabledChecks: ["memcached"], serviceUnits: ["memcached": bad])
            XCTAssertTrue(command.contains("svc_metric memcached memcached"))
            XCTAssertFalse(command.contains(bad.isEmpty ? "\u{0}" : bad))
        }
        for good in ["memcached-socket", "memcached@main", "php8.3-fpm", "my_unit.service"] {
            XCTAssertTrue(isValidServiceUnitName(good), good)
        }
    }

    /// The JSON key decodes, and the Preferences editor keeps it on save.
    func testServiceUnitsDecodeAndSurviveEditing() throws {
        let json = #"{"host":"example.com","service_units":{"memcached":"memcached-socket"}}"#
        let config = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.serviceUnits, ["memcached": "memcached-socket"])
        XCTAssertEqual(ServerEditor(from: config).toConfig()?.serviceUnits, config.serviceUnits)

        let plain = try JSONDecoder().decode(ServerConfig.self, from: Data(#"{"host":"example.com"}"#.utf8))
        XCTAssertTrue(plain.serviceUnits.isEmpty)
    }
}
