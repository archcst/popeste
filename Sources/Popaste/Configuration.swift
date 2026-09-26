import Foundation

struct Shortcut: Codable, Equatable {
    var code: UInt32 = 49
    var modifiers: UInt32 = 6144 // Control + Option
    var label = "⌃⌥Space"
}
enum PickerSize: String, Codable, CaseIterable {
    case small, medium, large
    var scale: Double { switch self { case .small: return 0.8; case .medium: return 0.9; case .large: return 1 } }
    var label: String { switch self { case .small: return "小"; case .medium: return "中"; case .large: return "大" } }
}
struct Preferences: Codable, Equatable {
    var version = 1
    var shortcut = Shortcut()
    var pickerSize = PickerSize.large
    var onboarded = false
    var launchAtLogin = false
    var appearance: String?
    var glassStyle: String?
    var resolvedGlassStyle: String { glassStyle == "regular" ? "regular" : "clear" }
    var language: String?
    var vimEditing: Bool?
    var navigationSchemes: [String]?
    var tagOrder: [String]?
    var tagColors: [String:String]?
    var resolvedNavigationSchemes: [String] { (navigationSchemes ?? ["arrows"]).filter { ["arrows", "emacs", "vim"].contains($0) } }
    static let supportedLanguages = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es"]
    static func resolveLanguage(_ selection: String?, preferred: [String] = Locale.preferredLanguages) -> String {
        if let selection, supportedLanguages.contains(selection) { return selection }
        for identifier in preferred {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
            guard let base = parts.first else { continue }
            if base == "zh" {
                return parts.contains("hant") || (!parts.contains("hans") && parts.contains(where: { ["tw", "hk", "mo"].contains($0) })) ? "zh-Hant" : "zh-Hans"
            }
            if supportedLanguages.contains(base) { return base }
        }
        return "en"
    }
    var resolvedLanguage: String { Self.resolveLanguage(language) }

}
enum LocalFiles {
    static var directory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/popeste", isDirectory: true) }
    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.deletingLastPathComponent().path) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
final class Configuration {
    let url: URL
    private(set) var value: Preferences
    var onChange: (() -> Void)?
    init(directory: URL = LocalFiles.directory, legacy: UserDefaults = .standard) throws {
        url = directory.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: url.path) {
            value = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
            guard value.version == 1 else { throw StoreError.version }
        } else {
            var initial = Preferences()
            if let data = legacy.data(forKey: "shortcut") { initial.shortcut = try JSONDecoder().decode(Shortcut.self, from: data) }
            initial.onboarded = legacy.bool(forKey: "onboarded")
            value = initial
            try persist(initial)
        }
    }
    private func persist(_ preferences: Preferences) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try LocalFiles.write(encoder.encode(preferences), to: url)
    }
    func update(_ change: (inout Preferences) -> Void) throws {
        var next = value; change(&next)
        try persist(next); value = next; onChange?()
    }
}

/// Keeps saved tag positions while appending new tags deterministically.
enum TagOrder {
    static func sorted(_ names: [String], preferred: [String]) -> [String] {
        let available = Prompt.normalizedTags(names)
        let saved = Prompt.normalizedTags(preferred).compactMap { name in available.first { $0.lowercased() == name.lowercased() } }
        let keys = Set(saved.map { $0.lowercased() })
        return saved + available.filter { !keys.contains($0.lowercased()) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    static func moving(_ name: String, before target: String?, in names: [String]) -> [String] {
        guard names.contains(name), target != name else { return names }
        var result = names.filter { $0 != name }
        let index = target.flatMap { result.firstIndex(of:$0) } ?? result.count
        result.insert(name,at:index); return result
    }
}

enum TagColor {
    static func normalized(_ input: String) -> String? {
        let value = input.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"#",with:"")
        guard value.count == 6, value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return "#"+value.uppercased()
    }
}
