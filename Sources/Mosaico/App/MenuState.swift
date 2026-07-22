import Combine

/// Stato osservabile per la menubar. Il contenuto della MenuBarExtra viene
/// rivalutato SOLO quando cambia stato osservato: tutto ciò che il menu
/// mostra deve passare da qui.
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var isPaused: Bool = false
    @Published var windows: [WindowManager.WindowInfo] = []
    @Published var staleRules: [WindowRule] = []
}
