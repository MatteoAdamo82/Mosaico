import AppKit

enum WindowDisposition {
    case tile
    case float
    case ignore
}

/// Attributi di una finestra rilevanti per la disposition: valori semplici,
/// così la decisione è una funzione pura e self-testabile.
struct WindowTraits {
    var role: String?
    var subrole: String?
    var title: String?
    var bundleID: String?
    var isResizable = true
    var isMovable = true
    var hasWindowParent = false
    var isFullscreen = false
    var isMinimized = false
    var cgLayer = 0
}

/// Decide come trattare una finestra: tile, float o ignora.
/// Port di float-system-windows.sh + esclusioni + euristiche PiP.
enum RulesEngine {

    /// Titoli delle finestre Picture-in-Picture nei vari browser/lingue.
    static let pipTitles: Set<String> = [
        "Picture in Picture", "Picture-in-Picture", "Immagine nell'immagine",
    ]

    /// Decisione pura sui soli attributi.
    static func disposition(traits: WindowTraits,
                            excludedBundleIDs: [String],
                            excludedWindowRules: [WindowRule]) -> WindowDisposition {
        // App esclusa dal tiling
        if let bundleID = traits.bundleID, excludedBundleIDs.contains(bundleID) {
            return .ignore
        }

        // Regola per finestra specifica (esclusa dall'utente via menu)
        if let bundleID = traits.bundleID, let title = traits.title,
           excludedWindowRules.contains(where: { $0.bundleID == bundleID && $0.title == title }) {
            return .ignore
        }

        // Finestre flottanti di sistema (PiP, palette always-on-top):
        // layer CGWindow ≠ 0 → mai tilare
        if traits.cgLayer != 0 {
            return .ignore
        }

        // PiP che (in alcune app) sta a layer 0: riconoscilo dal titolo
        if let title = traits.title, pipTitles.contains(title) {
            return .ignore
        }

        // Sheet/dialog agganciati a un'altra finestra: mai nel tree
        if traits.hasWindowParent {
            return .ignore
        }

        // Fullscreen nativo: escluso finché attivo
        if traits.isFullscreen {
            return .ignore
        }

        if traits.isMinimized {
            return .ignore
        }

        // Port di float-system-windows.sh
        let role = traits.role ?? ""
        let subrole = traits.subrole ?? ""

        guard role == kAXWindowRole || role.isEmpty else {
            return .ignore
        }

        switch subrole {
        case "AXDialog", "AXSystemDialog", "AXFloatingWindow":
            return .float
        case "AXStandardWindow":
            // Finestra a dimensione fissa o non spostabile (popup, palette,
            // finestre transitorie): float — tilarle strizza le altre per nulla
            guard traits.isResizable, traits.isMovable else { return .float }
            return .tile
        default:
            // Subrole vuoto o sconosciuto: float se anche role è vuoto o AXSheet
            if role.isEmpty || subrole == "AXSheet" {
                return .float
            }
            return .ignore
        }
    }

    /// Wrapper: legge gli attributi dalla finestra reale e decide.
    static func disposition(for window: AXWindow, bundleID: String?) -> WindowDisposition {
        let settings = SettingsStore.shared.settings
        let traits = WindowTraits(role: window.role,
                                  subrole: window.subrole,
                                  title: window.title,
                                  bundleID: bundleID,
                                  isResizable: window.isResizable,
                                  isMovable: window.isMovable,
                                  hasWindowParent: window.hasWindowParent,
                                  isFullscreen: window.isFullscreen,
                                  isMinimized: window.isMinimized,
                                  cgLayer: window.cgLayer)
        return disposition(traits: traits,
                           excludedBundleIDs: settings.excludedBundleIDs,
                           excludedWindowRules: settings.excludedWindowRules)
    }
}
