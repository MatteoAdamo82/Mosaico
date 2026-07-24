import Combine

/// Observable state for the menubar. The MenuBarExtra content is
/// re-evaluated ONLY when observed state changes: everything the menu
/// displays must go through here.
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var isPaused: Bool = false
    @Published var windows: [WindowManager.WindowInfo] = []
    @Published var staleRules: [WindowRule] = []
}
