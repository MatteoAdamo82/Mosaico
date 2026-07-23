import SwiftUI

/// Menu della menubar — stessa struttura di YabaiMenu, ma ogni azione
/// chiama il WindowManager in-process invece di shellare su yabai.
struct MenuContent: View {
    @ObservedObject private var menuState = MenuState.shared

    var body: some View {
        Section("Focus Finestra") {
            cmd(.focus(.south), "⌥J")
            cmd(.focus(.north), "⌥K")
            cmd(.focus(.west), "⌥H")
            cmd(.focus(.east), "⌥L")
        }

        Divider()

        Section("Focus Display") {
            cmd(.focusDisplay(.west), "⌥S")
            cmd(.focusDisplay(.east), "⌥G")
        }

        Divider()

        Section("Layout") {
            cmd(.rotate, "⇧⌥R")
            cmd(.mirrorY, "⇧⌥Y")
            cmd(.mirrorX, "⇧⌥X")
            cmd(.toggleFloat, "⇧⌥T")
            cmd(.toggleZoom, "⇧⌥M")
            cmd(.balance, "⇧⌥E")
        }

        Divider()

        Section("Swap Finestre") {
            cmd(.swap(.south), "⇧⌥J")
            cmd(.swap(.north), "⇧⌥K")
            cmd(.swap(.west), "⇧⌥H")
            cmd(.swap(.east), "⇧⌥L")
        }

        Divider()

        Section("Warp Finestre") {
            cmd(.warp(.south), "⌃⌥J")
            cmd(.warp(.north), "⌃⌥K")
            cmd(.warp(.west), "⌃⌥H")
            cmd(.warp(.east), "⌃⌥L")
        }

        Divider()

        Section("Sposta Finestra") {
            cmd(.moveToDisplay(.west), "⇧⌥S")
            cmd(.moveToDisplay(.east), "⇧⌥G")
        }

        Divider()

        Section("Mosaico") {
            Menu("Escludi finestra") {
                // ✓ = esclusa dal tiling; clicca per invertire
                ForEach(menuState.windows) { info in
                    Button("\(info.isExcluded ? "✓" : "　")  \(info.appName) — \(info.title)") {
                        WindowManager.shared.toggleExclusion(info.id)
                    }
                }

                if !menuState.staleRules.isEmpty {
                    Divider()
                    Section("Regole salvate (clicca per rimuovere)") {
                        ForEach(menuState.staleRules) { rule in
                            Button("✓  \(appDisplayName(for: rule.bundleID)) — \(rule.title)") {
                                WindowManager.shared.removeExclusionRule(rule)
                            }
                        }
                    }
                }
            }

            Button("⌃⌥Q  \(menuState.isPaused ? "▶ Riprendi Tiling" : "⏸ Pausa Tiling")") {
                WindowManager.shared.perform(.pauseResume)
            }
            cmd(.retileAll, "⌃⌥R")

            Button("Impostazioni…") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        Divider()

        Button("Esci da Mosaico") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func cmd(_ command: Command, _ shortcut: String) -> some View {
        Button("\(shortcut)  \(command.title)") {
            WindowManager.shared.perform(command)
        }
    }

    private func appDisplayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }
}
