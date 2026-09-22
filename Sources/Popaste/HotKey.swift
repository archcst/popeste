import AppKit
import Carbon

final class HotKey {
    var action: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var shortcut: Shortcut
    let configuration: Configuration
    init(configuration: Configuration) {
        self.configuration = configuration
        shortcut = configuration.value.shortcut
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ next: Shortcut) throws {
        if reference != nil && shortcut.code == next.code && shortcut.modifiers == next.modifiers { return }
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(next.code, next.modifiers, EventHotKeyID(signature: 0x504F5041, id: 1), GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr else { throw NSError(domain: "Popaste", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "此快捷键无法注册，可能已被占用。原快捷键保持有效。请尝试其他组合。"] ) }
        do { try configuration.update { $0.shortcut = next } }
        catch { if let newRef { UnregisterEventHotKey(newRef) }; throw error }
        if let reference { UnregisterEventHotKey(reference) }
        reference = newRef; shortcut = next
    }
    deinit { if let reference { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) } }
}
final class Recorder: NSButton {
    var recorded: ((Shortcut) -> Void)?
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { recording = true; title = "请按组合键（Esc 取消）"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { return }
        if event.keyCode == 53 { recording = false; recorded?(Shortcut(code: UInt32.max, label: "")); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.control, .option, .command]).isEmpty,
              ![36, 48, 51, 53, 123, 124, 125, 126].contains(Int(event.keyCode)) else { title = "请使用 ⌃ / ⌥ / ⌘ + 字符键"; return }
        var mods: UInt32 = 0; var label = ""
        for (flag, carbon, text) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
            if flags.contains(flag) { mods |= UInt32(carbon); label += text }
        }
        label += event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers ?? "键 \(event.keyCode)").uppercased()
        recording = false; recorded?(Shortcut(code: UInt32(event.keyCode), modifiers: mods, label: label))
    }
}
