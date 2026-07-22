import AppKit

enum WindowDisposition {
    case tile
    case float
    case ignore
}

/// Decide come trattare una finestra: tile, float o ignora.
/// Port di float-system-windows.sh + esclusioni per bundle ID.
enum RulesEngine {

    /// Titoli delle finestre Picture-in-Picture nei vari browser/lingue.
    private static let pipTitles: Set<String> = [
        "Picture in Picture", "Picture-in-Picture", "Immagine nell'immagine",
    ]

    static func disposition(for window: AXWindow, bundleID: String?) -> WindowDisposition {
        let settings = SettingsStore.shared.settings

        // App esclusa dal tiling
        if let bundleID, settings.excludedBundleIDs.contains(bundleID) {
            return .ignore
        }

        // Regola per finestra specifica (esclusa dall'utente via menu)
        if let bundleID, let title = window.title,
           settings.excludedWindowRules.contains(where: { $0.bundleID == bundleID && $0.title == title }) {
            return .ignore
        }

        // Finestre flottanti di sistema (PiP, palette always-on-top):
        // layer CGWindow ≠ 0 → mai tilare
        if window.cgLayer != 0 {
            return .ignore
        }

        // PiP che (in alcune app) sta a layer 0: riconoscilo dal titolo
        if let title = window.title, pipTitles.contains(title) {
            return .ignore
        }

        // Sheet/dialog agganciati a un'altra finestra: mai nel tree
        if window.hasWindowParent {
            return .ignore
        }

        // Fullscreen nativo: escluso finché attivo
        if window.isFullscreen {
            return .ignore
        }

        if window.isMinimized {
            return .ignore
        }

        // Port di float-system-windows.sh
        let role = window.role ?? ""
        let subrole = window.subrole ?? ""

        guard role == kAXWindowRole || role.isEmpty else {
            return .ignore
        }

        switch subrole {
        case "AXDialog", "AXSystemDialog", "AXFloatingWindow":
            return .float
        case "AXStandardWindow":
            // Finestra a dimensione fissa o non spostabile (popup, palette,
            // finestre transitorie): float — tilarle strizza le altre per nulla
            guard window.isResizable, window.isMovable else { return .float }
            return .tile
        default:
            // Subrole vuoto o sconosciuto: float se anche role è vuoto o AXSheet
            if role.isEmpty || subrole == "AXSheet" {
                return .float
            }
            return .ignore
        }
    }
}
