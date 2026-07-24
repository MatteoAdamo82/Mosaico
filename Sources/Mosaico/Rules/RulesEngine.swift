import AppKit

enum WindowDisposition {
    case tile
    case float
    case ignore
}

/// Window attributes relevant to the disposition: simple values,
/// so the decision is a pure and self-testable function.
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

/// Decides how to treat a window: tile, float or ignore.
/// Port of float-system-windows.sh + exclusions + PiP heuristics.
enum RulesEngine {

    /// Titles of Picture-in-Picture windows across the various browsers/languages.
    static let pipTitles: Set<String> = [
        "Picture in Picture", "Picture-in-Picture", "Immagine nell'immagine",
    ]

    /// Pure decision based on attributes only.
    static func disposition(traits: WindowTraits,
                            excludedBundleIDs: [String],
                            excludedWindowRules: [WindowRule]) -> WindowDisposition {
        // App excluded from tiling
        if let bundleID = traits.bundleID, excludedBundleIDs.contains(bundleID) {
            return .ignore
        }

        // Rule for a specific window (excluded by the user via menu)
        if let bundleID = traits.bundleID, let title = traits.title,
           excludedWindowRules.contains(where: { $0.bundleID == bundleID && $0.title == title }) {
            return .ignore
        }

        // System floating windows (PiP, always-on-top palettes):
        // CGWindow layer ≠ 0 → never tile
        if traits.cgLayer != 0 {
            return .ignore
        }

        // PiP that (in some apps) sits at layer 0: recognize it by title
        if let title = traits.title, pipTitles.contains(title) {
            return .ignore
        }

        // Sheets/dialogs attached to another window: never in the tree
        if traits.hasWindowParent {
            return .ignore
        }

        // Native fullscreen: excluded while active
        if traits.isFullscreen {
            return .ignore
        }

        if traits.isMinimized {
            return .ignore
        }

        // Port of float-system-windows.sh
        let role = traits.role ?? ""
        let subrole = traits.subrole ?? ""

        guard role == kAXWindowRole || role.isEmpty else {
            return .ignore
        }

        switch subrole {
        case "AXDialog", "AXSystemDialog", "AXFloatingWindow":
            return .float
        case "AXStandardWindow":
            // Fixed-size or non-movable window (popups, palettes,
            // transient windows): float — tiling them squeezes the others for nothing
            guard traits.isResizable, traits.isMovable else { return .float }
            return .tile
        default:
            // Empty or unknown subrole: float if role is also empty or AXSheet
            if role.isEmpty || subrole == "AXSheet" {
                return .float
            }
            return .ignore
        }
    }

    /// Wrapper: reads the attributes from the real window and decides.
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
