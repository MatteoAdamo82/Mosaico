import Foundation
import ServiceManagement

/// Launch at login, via SMAppService. Observable so menu and settings always
/// show the real state (the system can also change it behind our back, e.g.
/// when the user revokes it in System Settings › Login Items).
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var isEnabled: Bool = false
    /// macOS registered it but the user must still approve it in
    /// System Settings › General › Login Items.
    @Published private(set) var needsApproval: Bool = false

    private init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled)
        needsApproval = (status == .requiresApproval)
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            MosaicoLog.log("login item \(enabled ? "on" : "off") → status=\(SMAppService.mainApp.status.rawValue)")
        } catch {
            MosaicoLog.log("login item error: \(error.localizedDescription)")
        }
        refresh()
    }

    func toggle() {
        set(!isEnabled)
    }

    /// Opens the system pane where the user can approve/revoke the item.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
