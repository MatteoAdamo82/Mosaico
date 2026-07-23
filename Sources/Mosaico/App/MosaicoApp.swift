import SwiftUI

@main
enum Main {
    static func main() {
        // XCTest assente con soli CommandLineTools: i test del BSP tree
        // girano in-process con `.build/debug/Mosaico --selftest`
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--diag") {
            Diagnostics.run()
            exit(0)
        }
        MosaicoApp.main()
    }
}

struct MosaicoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var menuState = MenuState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            // Mini-mosaico aureo; attenuato quando il tiling è in pausa
            Image(nsImage: menuState.isPaused ? MenuBarIcon.paused : MenuBarIcon.normal)
        }
        .menuBarExtraStyle(.menu)
    }
}
