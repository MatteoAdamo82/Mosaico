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
                Section("Gestite (clicca per escludere)") {
                    ForEach(WindowManager.shared.managedWindowsSnapshot()) { info in
                        Button("\(info.appName) — \(info.title)") {
                            WindowManager.shared.excludeWindow(info.id)
                        }
                    }
                }

                let rules = SettingsStore.shared.settings.excludedWindowRules
                if !rules.isEmpty {
                    Divider()
                    Section("Escluse (clicca per riabilitare)") {
                        ForEach(rules) { rule in
                            Button("✓  \(appDisplayName(for: rule.bundleID)) — \(rule.title)") {
                                WindowManager.shared.removeExclusionRule(rule)
                            }
                        }
                    }
                }
            }

            Button("⌃⌥Q  \(menuState.isPaused ? "Riprendi Tiling" : "Pausa Tiling")") {
                WindowManager.shared.perform(.pauseResume)
            }
            cmd(.retileAll, "⌃⌥R")

            Button("Impostazioni…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
