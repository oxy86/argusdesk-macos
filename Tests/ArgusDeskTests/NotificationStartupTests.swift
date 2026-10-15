import Dispatch
import XCTest
@testable import ArgusDesk

/// Reproduces the installed-app path: alerts are enabled before startup and
/// the permission result arrives on a system background queue, not MainActor.
final class NotificationStartupTests: XCTestCase {
    func testEnabledAtStartupAcceptsBackgroundAuthorizationCallback() async {
        let completed = await withCheckedContinuation { continuation in
            Task { @MainActor in
                let controller = NotificationController(authorizationRequest: { completion in
                    DispatchQueue.global().async {
                        completion(true, nil)
                        continuation.resume(returning: true)
                    }
                })
                controller.configure(notificationsEnabled: true, recoveryNotificationsEnabled: true)
            }
        }
        XCTAssertTrue(completed)
    }
}
