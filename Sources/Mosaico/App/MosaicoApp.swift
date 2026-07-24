import SwiftUI

@main
enum Main {
    static func main() {
        // XCTest is absent with only CommandLineTools: the BSP tree tests
        // run in-process with `.build/debug/Mosaico --selftest`
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
            // Golden-ratio mini-mosaic; dimmed when tiling is paused
            Image(nsImage: menuState.isPaused ? MenuBarIcon.paused : MenuBarIcon.normal)
        }
        .menuBarExtraStyle(.menu)
    }
}
