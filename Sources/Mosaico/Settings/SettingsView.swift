import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Generale", systemImage: "gearshape") }
            HotkeySettingsView()
                .tabItem { Label("Scorciatoie", systemImage: "keyboard") }
            ExclusionSettingsView()
                .tabItem { Label("App escluse", systemImage: "rectangle.slash") }
        }
        .frame(width: 520, height: 440)
    }
}

// MARK: - Generale

private struct GeneralSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("Layout") {
                LabeledContent("Spazio dai bordi: \(Int(store.settings.padding))px") {
                    Slider(value: $store.settings.padding, in: 0...40, step: 1)
                        .frame(width: 220)
                }
                LabeledContent("Spazio tra finestre: \(Int(store.settings.gap))px") {
                    Slider(value: $store.settings.gap, in: 0...40, step: 1)
                        .frame(width: 220)
                }
            }

            Section("Mouse") {
                Toggle("Il puntatore segue la finestra attiva", isOn: $store.settings.mouseFollowsFocus)
            }

            Section("Avvio") {
                Toggle("Avvia Mosaico al login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { enable in
                        do {
                            if enable {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            NSLog("Mosaico: login item error: \(error)")
                        }
                        store.settings.launchAtLogin = enable
                    }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scorciatoie

/// Stato UI senza @State: il toolchain CommandLineTools non espande le
/// macro SwiftUI (SwiftUIMacros plugin assente), quindi ObservableObject.
private final class UIState<Value>: ObservableObject {
    @Published var value: Value
    init(_ initial: Value) { value = initial }
    var binding: Binding<Value> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}

private struct HotkeySettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var recording = UIState<String?>(nil)
    private var recordingID: String? { recording.value }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.settings.bindings) { binding in
                    HStack {
                        Text(binding.command.title)
                        Spacer()
                        Button {
                            recording.value = (recordingID == binding.id) ? nil : binding.id
                        } label: {
                            Text(recordingID == binding.id ? "Premi i tasti…" : binding.displayString)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(recordingID == binding.id ? Color.accentColor : .primary)
                                .frame(minWidth: 90)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .background(KeyRecorder(recordingID: recording.binding, store: store))

            Divider()

            HStack {
                Button("Ripristina preset di default") {
                    store.settings.bindings = KeyBinding.defaultPreset
                }
                Spacer()
            }
            .padding(12)
        }
    }
}

/// Cattura la combinazione premuta mentre `recordingID` è attivo.
private struct KeyRecorder: NSViewRepresentable {
    let recordingID: Binding<String?>
    let store: SettingsStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: KeyRecorder
        private var monitor: Any?

        init(parent: KeyRecorder) {
            self.parent = parent
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let id = self.parent.recordingID.wrappedValue else { return event }

                var carbonMods: UInt32 = 0
                if event.modifierFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
                if event.modifierFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
                if event.modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
                if event.modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }

                var settings = self.parent.store.settings
                if let index = settings.bindings.firstIndex(where: { $0.id == id }) {
                    settings.bindings[index].keyCode = UInt32(event.keyCode)
                    settings.bindings[index].carbonModifiers = carbonMods
                    self.parent.store.settings = settings
                }
                DispatchQueue.main.async { self.parent.recordingID.wrappedValue = nil }
                return nil   // consuma l'evento
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

// MARK: - App escluse

private struct ExclusionSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var selected = UIState<String?>(nil)
    private var selection: String? { selected.value }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selected.binding) {
                Section("App escluse") {
                    ForEach(store.settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            appIcon(for: bundleID)
                            VStack(alignment: .leading) {
                                Text(appName(for: bundleID))
                                Text(bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(bundleID)
                    }
                }

                if !store.settings.excludedWindowRules.isEmpty {
                    Section("Finestre escluse") {
                        ForEach(store.settings.excludedWindowRules) { rule in
                            HStack {
                                appIcon(for: rule.bundleID)
                                VStack(alignment: .leading) {
                                    Text(rule.title)
                                    Text("\(appName(for: rule.bundleID)) — solo questa finestra")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    store.settings.excludedWindowRules.removeAll { $0 == rule }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Menu("Aggiungi app in esecuzione…") {
                    ForEach(runningApps(), id: \.self) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            guard let id = app.bundleIdentifier,
                                  !store.settings.excludedBundleIDs.contains(id) else { return }
                            store.settings.excludedBundleIDs.append(id)
                        }
                    }
                }
                .frame(width: 220)

                Button("Rimuovi") {
                    if let selection {
                        store.settings.excludedBundleIDs.removeAll { $0 == selection }
                    }
                }
                .disabled(selection == nil)

                Spacer()
            }
            .padding(12)
        }
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 24, height: 24)
        }
    }
}

// MARK: - Display helpers

extension KeyBinding {
    /// Rappresentazione leggibile (⌃⌥⇧⌘ + tasto).
    var displayString: String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + KeyBinding.keyName(for: keyCode)
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_0): "0",
        ]
        return names[keyCode] ?? "key\(keyCode)"
    }
}
