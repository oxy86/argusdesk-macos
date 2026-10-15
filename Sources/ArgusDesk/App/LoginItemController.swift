import ServiceManagement

/// Native login-item registration. The OS remains the source of truth and can
/// require user approval in System Settings. No agent or helper is installed.
@MainActor
struct LoginItemController {
    var enabled: Bool { SMAppService.mainApp.status == .enabled }
    var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}
