import Combine

/// Stato osservabile per la menubar.
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var isPaused: Bool = false
}
