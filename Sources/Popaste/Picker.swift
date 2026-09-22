import AppKit

final class PickerPanel: NSPanel { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { false } }
final class Picker: NSObject {
    let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 510, height: 410), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let store: Store
    let configuration: Configuration
    let interface = WebInterface(mode: "picker")
    let insertion = Insertion()
    var manage: (() -> Void)?
    var settings: (() -> Void)?
    var create: (() -> Void)?
    private var monitors: [Any] = []
    private var busy = false
    init(store: Store, configuration: Configuration) {
        self.store = store; self.configuration = configuration; super.init()
        panel.title = "Popaste · 选择提示词"; panel.level = .popUpMenu; panel.hasShadow = true; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
        interface.view.frame = panel.contentView!.bounds; panel.contentView = interface.view
        interface.action = { [weak self] name, payload in
            guard let self else { return }
            switch name {
            case "ready": self.reload()
            case "dismiss": self.dismiss(restore: true)
            case "insert": if let id = payload["id"] as? String, let prompt = self.store.prompts.first(where: { $0.id.uuidString == id }) { self.confirm(prompt) }
            case "new": self.dismiss(restore: false); self.create?()
            case "settings": self.dismiss(restore: false); self.settings?()
            case "copy": if let body = payload["body"] as? String { copyText(body); self.dismiss(restore: true) }
            default: break
            }
        }
    }
    func toggle() { panel.isVisible ? dismiss(restore: true) : show() }
    func show() {
        guard !busy else { return }
        let caret = insertion.capture(), mouse = NSEvent.mouseLocation
        let point = caret.map { NSPoint(x: $0.minX, y: $0.minY) } ?? mouse
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main!
        let scale = configuration.value.pickerSize.scale
        panel.setFrame(PickerPlacement.frame(caret: caret, mouse: mouse, visibleScreen: screen.visibleFrame, desiredSize: NSSize(width: 510*scale, height: 410*scale)), display: false)
        reload(); interface.open(); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(interface.view)
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if let self, event.window !== self.panel { self.dismiss(restore: false) }; return event
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.dismiss(restore: false) }) { monitors.append(m) }
    }
    func dismiss(restore: Bool) { panel.orderOut(nil); monitors.forEach(NSEvent.removeMonitor); monitors.removeAll(); if restore { insertion.restore() } }
    func reload() { interface.state = ["prompts": interfacePrompts(store.search("")), "scale": configuration.value.pickerSize.scale, "dark": interfaceDark(configuration.value.appearance ?? "system")] }
    private func confirm(_ prompt: Prompt) {
        guard !busy, panel.isVisible else { return }; busy = true; dismiss(restore: false)
        insertion.paste(prompt.body) { [weak self] success in
            guard let self else { return }; self.busy = false
            if success { do { try self.store.used(prompt.id) } catch { showError(error) } }
            else {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert(); alert.messageText = "无法自动插入"; alert.informativeText = "请检查辅助功能权限，并保持原输入窗口可用。你可以复制正文后手动粘贴。"; alert.addButton(withTitle: "复制正文"); alert.addButton(withTitle: "取消")
                if alert.runModal() == .alertFirstButtonReturn { copyText(prompt.body) }
            }
        }
    }
}
