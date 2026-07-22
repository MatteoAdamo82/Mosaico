import Foundation
import Combine

/// Regola di esclusione per una finestra specifica (app + titolo esatto).
struct WindowRule: Codable, Equatable, Hashable, Identifiable {
    var bundleID: String
    var title: String
    var id: String { bundleID + "|" + title }
}

/// Wrapper che assorbe elementi non decodificabili (es. binding salvati che
/// riferiscono comandi rimossi) senza far fallire l'intero array.
private struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}

struct MosaicoSettings: Codable, Equatable {
    var padding: Double = 7
    var gap: Double = 7
    var mouseFollowsFocus: Bool = true
    var excludedBundleIDs: [String] = MosaicoSettings.defaultExclusions
    var excludedWindowRules: [WindowRule] = []
    var bindings: [KeyBinding] = KeyBinding.defaultPreset
    var launchAtLogin: Bool = false

    init() {}

    // Decodifica tollerante: campi assenti → default; binding singoli
    // invalidi → scartati senza azzerare il resto.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? 7
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 7
        mouseFollowsFocus = try c.decodeIfPresent(Bool.self, forKey: .mouseFollowsFocus) ?? true
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? MosaicoSettings.defaultExclusions
        excludedWindowRules = try c.decodeIfPresent([WindowRule].self, forKey: .excludedWindowRules) ?? []
        let decoded = (try c.decodeIfPresent([Failable<KeyBinding>].self, forKey: .bindings))?.compactMap(\.value) ?? []
        bindings = decoded.isEmpty ? KeyBinding.defaultPreset : decoded
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }

    static let defaultExclusions: [String] = [
        "com.apple.systempreferences",
        "com.colliderli.iina",
        "com.apple.calculator",
        "org.pqrs.Karabiner-Elements.Settings",
        "com.apple.archiveutility",
        "com.apple.AppStore",
        "com.apple.audio.AudioMIDISetup",
    ]
}

/// Persistenza JSON in ~/Library/Application Support/Mosaico/settings.json.
/// Osservabile: i manager si ri-configurano quando le impostazioni cambiano.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: MosaicoSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            NotificationCenter.default.post(name: .mosaicoSettingsChanged, object: nil)
        }
    }

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mosaico", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(MosaicoSettings.self, from: data) {
            settings = loaded
        } else {
            settings = MosaicoSettings()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

extension Notification.Name {
    static let mosaicoSettingsChanged = Notification.Name("mosaicoSettingsChanged")
}
