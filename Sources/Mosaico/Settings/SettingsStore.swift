import Foundation
import Combine

/// Exclusion rule for a specific window (app + exact title).
struct WindowRule: Codable, Equatable, Hashable, Identifiable {
    var bundleID: String
    var title: String
    var id: String { bundleID + "|" + title }
}

/// Wrapper that absorbs undecodable elements (e.g. saved bindings that
/// reference removed commands) without failing the entire array.
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

    // Tolerant decoding: absent fields → default; individual invalid
    // bindings → discarded without wiping out the rest.
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

/// JSON persistence in ~/Library/Application Support/Mosaico/settings.json.
/// Observable: managers reconfigure themselves when settings change.
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
