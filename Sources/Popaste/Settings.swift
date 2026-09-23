import AppKit
import ServiceManagement
import ApplicationServices

final class Settings {
    let hotKey: HotKey
    let configuration: Configuration
    init(hotKey: HotKey, configuration: Configuration) { self.hotKey = hotKey; self.configuration = configuration }
    func handle(_ name: String, _ payload: [String: Any]) throws {
        switch name {
        case "size": if let value = payload["value"] as? String, let size = PickerSize(rawValue: value) { try configuration.update { $0.pickerSize = size } }
        case "appearance": if let value = payload["value"] as? String, ["system", "light", "dark"].contains(value) { try configuration.update { $0.appearance = value } }
        case "navigationSchemes": if let value = payload["value"] as? [String], value.allSatisfy({ ["arrows", "emacs", "vim"].contains($0) }) { try configuration.update { $0.navigationSchemes = value } }
        case "language": if let value = payload["value"] as? String, (["system"] + Preferences.supportedLanguages).contains(value) { try configuration.update { $0.language = value } }
        case "openDirectory":
            let directory = configuration.url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !NSWorkspace.shared.open(directory) { throw NSError(domain: "Popaste", code: 2, userInfo: [NSLocalizedDescriptionKey: tr("无法打开配置目录。")]) }
        case "shortcut": try record(payload)
        case "login":
            if payload["enabled"] as? Bool == true { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            try configuration.update { $0.launchAtLogin = SMAppService.mainApp.status == .enabled }
        case "permission":
            if !AXIsProcessTrusted() { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        default: break
        }
    }
    private func record(_ payload: [String: Any]) throws {
        let codes: [String: UInt32] = ["KeyA":0,"KeyS":1,"KeyD":2,"KeyF":3,"KeyH":4,"KeyG":5,"KeyZ":6,"KeyX":7,"KeyC":8,"KeyV":9,"KeyB":11,"KeyQ":12,"KeyW":13,"KeyE":14,"KeyR":15,"KeyY":16,"KeyT":17,"Digit1":18,"Digit2":19,"Digit3":20,"Digit4":21,"Digit6":22,"Digit5":23,"Equal":24,"Digit9":25,"Digit7":26,"Minus":27,"Digit8":28,"Digit0":29,"BracketRight":30,"KeyO":31,"KeyU":32,"BracketLeft":33,"KeyI":34,"KeyP":35,"KeyL":37,"KeyJ":38,"Quote":39,"KeyK":40,"Semicolon":41,"Backslash":42,"Comma":43,"Slash":44,"KeyN":45,"KeyM":46,"Period":47,"Space":49,"Backquote":50]
        guard let key = payload["code"] as? String, let code = codes[key] else { throw invalidShortcut() }
        var modifiers: UInt32 = 0, label = ""
        for (name, mask, symbol) in [("control", UInt32(4096), "⌃"), ("option", UInt32(2048), "⌥"), ("shift", UInt32(512), "⇧"), ("command", UInt32(256), "⌘")] {
            if payload[name] as? Bool == true { modifiers |= mask; label += symbol }
        }
        guard modifiers & (4096 | 2048 | 256) != 0 else { throw invalidShortcut() }
        label += key.hasPrefix("Key") ? String(key.dropFirst(3)) : key.hasPrefix("Digit") ? String(key.dropFirst(5)) : key
        try hotKey.register(Shortcut(code: code, modifiers: modifiers, label: label))
    }
    private func invalidShortcut() -> Error { NSError(domain: "Popaste", code: 1, userInfo: [NSLocalizedDescriptionKey: tr("请使用 ⌃ / ⌥ / ⌘ 加字符键或空格。原快捷键保持有效。")]) }
    var state: [String: Any] {
        ["navigationSchemes": configuration.value.resolvedNavigationSchemes, "language": configuration.value.language ?? "system", "resolvedLanguage": configuration.value.resolvedLanguage, "prompts": [], "shortcut": hotKey.shortcut.label, "size": configuration.value.pickerSize.rawValue, "trusted": AXIsProcessTrusted(), "login": SMAppService.mainApp.status == .enabled, "loginPending": SMAppService.mainApp.status == .requiresApproval, "appearance": configuration.value.appearance ?? "system", "dark": interfaceDark(configuration.value.appearance ?? "system")]
    }
}
