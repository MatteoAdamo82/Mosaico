import Foundation

enum Direction: String, Codable, CaseIterable {
    case west, south, north, east
}

/// Tutte le azioni eseguibili, invocate da hotkey e menubar.
enum Command: Codable, Equatable, Hashable {
    case focus(Direction)
    case focusDisplay(Direction)      // solo west/east
    case swap(Direction)
    case warp(Direction)
    case rotate                       // 270°, come yabai --rotate 270
    case mirrorX
    case mirrorY
    case balance
    case toggleFloat
    case toggleZoom
    case moveToDisplay(Direction)     // solo west/east, poi focus segue
    case moveToWorkspace(Int)
    case moveToWorkspacePrev
    case moveToWorkspaceNext
    case pauseResume
    case retileAll

    /// Titolo per menu e settings.
    var title: String {
        switch self {
        case .focus(let d): return "Focus \(d.italian)"
        case .focusDisplay(let d): return "Focus Display \(d.italian)"
        case .swap(let d): return "Swap \(d.italian)"
        case .warp(let d): return "Warp \(d.italian)"
        case .rotate: return "Ruota Layout"
        case .mirrorX: return "Specchia Asse X"
        case .mirrorY: return "Specchia Asse Y"
        case .balance: return "Ribilancia Finestre"
        case .toggleFloat: return "Toggle Float"
        case .toggleZoom: return "Massimizza/Ripristina"
        case .moveToDisplay(let d): return "Sposta su Display \(d.italian)"
        case .moveToWorkspace(let n): return "Sposta su Spazio \(n)"
        case .moveToWorkspacePrev: return "Sposta su Spazio Precedente"
        case .moveToWorkspaceNext: return "Sposta su Spazio Successivo"
        case .pauseResume: return "Pausa/Riprendi Tiling"
        case .retileAll: return "Ricalcola Tiling"
        }
    }
}

extension Direction {
    var italian: String {
        switch self {
        case .west: return "Ovest"
        case .south: return "Sud"
        case .north: return "Nord"
        case .east: return "Est"
        }
    }
}
