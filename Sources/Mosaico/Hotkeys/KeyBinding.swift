import Carbon.HIToolbox
import Foundation

struct KeyBinding: Codable, Equatable, Hashable, Identifiable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var command: Command

    var id: String { "\(keyCode)-\(carbonModifiers)" }

    /// Preset di default: traduzione 1:1 di skhdrc + switch workspace ctrl-1..7.
    static let defaultPreset: [KeyBinding] = {
        let alt = UInt32(optionKey)
        let shiftAlt = UInt32(optionKey | shiftKey)
        let ctrlAlt = UInt32(optionKey | controlKey)

        var b: [KeyBinding] = []

        // Focus finestra: alt-hjkl
        b.append(.init(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: alt, command: .focus(.west)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: alt, command: .focus(.south)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: alt, command: .focus(.north)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_L), carbonModifiers: alt, command: .focus(.east)))

        // Focus display: alt-s/g
        b.append(.init(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: alt, command: .focusDisplay(.west)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_G), carbonModifiers: alt, command: .focusDisplay(.east)))

        // Layout: shift+alt r/y/x/t/m/e
        b.append(.init(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: shiftAlt, command: .rotate))
        b.append(.init(keyCode: UInt32(kVK_ANSI_Y), carbonModifiers: shiftAlt, command: .mirrorY))
        b.append(.init(keyCode: UInt32(kVK_ANSI_X), carbonModifiers: shiftAlt, command: .mirrorX))
        b.append(.init(keyCode: UInt32(kVK_ANSI_T), carbonModifiers: shiftAlt, command: .toggleFloat))
        b.append(.init(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: shiftAlt, command: .toggleZoom))
        b.append(.init(keyCode: UInt32(kVK_ANSI_E), carbonModifiers: shiftAlt, command: .balance))

        // Swap: shift+alt-hjkl
        b.append(.init(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: shiftAlt, command: .swap(.west)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: shiftAlt, command: .swap(.south)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: shiftAlt, command: .swap(.north)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_L), carbonModifiers: shiftAlt, command: .swap(.east)))

        // Warp: ctrl+alt-hjkl
        b.append(.init(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: ctrlAlt, command: .warp(.west)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: ctrlAlt, command: .warp(.south)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: ctrlAlt, command: .warp(.north)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_L), carbonModifiers: ctrlAlt, command: .warp(.east)))

        // Sposta su display: shift+alt-s/g
        b.append(.init(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: shiftAlt, command: .moveToDisplay(.west)))
        b.append(.init(keyCode: UInt32(kVK_ANSI_G), carbonModifiers: shiftAlt, command: .moveToDisplay(.east)))

        // Sposta su workspace prev/next: shift+alt-p/n
        b.append(.init(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: shiftAlt, command: .moveToWorkspacePrev))
        b.append(.init(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: shiftAlt, command: .moveToWorkspaceNext))

        // Sposta su space nativo 1..7: shift+alt-1..7.
        // Lo switch di space resta a Mission Control (Ctrl+N di sistema).
        let digits: [Int] = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7]
        for (i, key) in digits.enumerated() {
            b.append(.init(keyCode: UInt32(key), carbonModifiers: shiftAlt, command: .moveToWorkspace(i + 1)))
        }

        // Servizio: ctrl+alt-q pausa, ctrl+alt-r retile
        b.append(.init(keyCode: UInt32(kVK_ANSI_Q), carbonModifiers: ctrlAlt, command: .pauseResume))
        b.append(.init(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: ctrlAlt, command: .retileAll))

        return b
    }()
}
