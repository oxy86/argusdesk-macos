import Foundation
import XCTest
@testable import ArgusDesk

/// PHP-FPM thresholds must affect both metric colors and notification content.
final class PHPFPMThresholdTests: XCTestCase {
    func testPHPOverridesSharedServiceThresholds() {
        let thresholds = Thresholds(serviceCPUWarningPercent: 10, serviceCPUErrorPercent: 25,
                                    phpFPMCPUWarningPercent: 40, phpFPMCPUErrorPercent: 60)
        let engine = SeverityEngine(thresholds: thresholds)
        let metrics = engine.evaluate(metrics: [
            Metric(label: "php-fpm", value: "active 2.00GB 30.0%", severity: .ok),
            Metric(label: "nginx", value: "active 0.25GB 30.0%", severity: .ok)
        ])
        XCTAssertEqual(metrics[0].severity, .ok)
        XCTAssertEqual(metrics[1].severity, .error)
        let php = engine.evaluate(metrics: [Metric(label: "php-fpm", value: "active 2.00GB 60.0%", severity: .ok)])
        XCTAssertEqual(php[0].severity, .error)
        var alerts = MetricAlerts()
        let result = alerts.evaluate(servers: [ServerStatus(name: "example", severity: .error, headline: "", metrics: php)],
                                     thresholds: thresholds, recovery: true)
        XCTAssertTrue(result[0].body.contains("60% CPU"))
    }

    func testPersistedPHPOverridesAndMigration() throws {
        let domain = "ArgusDeskTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let fallback = AppPreferences(localRefreshSeconds: 5, remoteRefreshSeconds: 60, overlayWidth: 380,
                                     configFilePath: nil, notificationsEnabled: false, recoveryNotificationsEnabled: true,
                                     thresholds: .default)
        defaults.set(15.0, forKey: "serviceCPUWarningPercent")
        defaults.set(35.0, forKey: "serviceCPUErrorPercent")
        let store = PreferencesStore(defaults: defaults)
        let migrated = store.load(fallback: fallback)
        XCTAssertEqual(migrated.thresholds.phpFPMCPUWarningPercent, 50)
        XCTAssertEqual(migrated.thresholds.phpFPMCPUErrorPercent, 90)
        let changed = AppPreferences(localRefreshSeconds: 5, remoteRefreshSeconds: 60, overlayWidth: 380,
                                    configFilePath: nil, notificationsEnabled: false, recoveryNotificationsEnabled: true,
                                    thresholds: Thresholds(phpFPMCPUWarningPercent: 40, phpFPMCPUErrorPercent: 75))
        store.save(changed)
        XCTAssertEqual(store.load(fallback: fallback).thresholds.phpFPMCPUWarningPercent, 40)
        XCTAssertEqual(store.load(fallback: fallback).thresholds.phpFPMCPUErrorPercent, 75)
    }
}
