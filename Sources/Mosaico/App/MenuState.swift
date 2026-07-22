import Combine

/// Stato osservabile per la menubar: spazio attivo e pausa.
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var activeWorkspace: Int = 1
    @Published var isPaused: Bool = false
}
