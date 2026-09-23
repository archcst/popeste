import AppKit

final class PickerPanel: NSPanel { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { false } }
final class Picker: NSObject {
    let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 424), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let store: Store
    let configuration: Configuration
    let settings: Settings
    let manager: Manager
    let interface = WebInterface(mode: "list")
    let insertion = Insertion()
    private var monitors: [Any] = []
    private var busy = false
    private var modal = false
    private var recording = false
    init(store: Store, configuration: Configuration, settings: Settings) {
        self.store = store; self.configuration = configuration; self.settings = settings
        manager = Manager(store: store)
        super.init()
        panel.title = "Popaste"; panel.level = .popUpMenu; panel.hasShadow = true; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
        interface.view.frame = panel.contentView!.bounds; panel.contentView = interface.view
        interface.action = { [weak self] name, payload in self?.handle(name, payload) }
        store.onChange = { [weak self] in self?.reload() }
        configuration.onChange = { [weak self] in self?.resize(); self?.reload() }
    }
    private func handle(_ name: String, _ payload: [String: Any]) {
        do {
            switch name {
            case "ready", "refresh": reload()
            case "recording": recording = payload["enabled"] as? Bool ?? false
            case "draft": manager.receive(payload)
            case "discard": manager.draft = PromptDraft()
            case "save":
                manager.receive(payload)
                let prompt = try manager.save(); reload(); interface.call("nativeSaved", prompt.id.uuidString)
            case "delete":
                if let id = (payload["id"] as? String).flatMap(UUID.init(uuidString:)) {
                    try store.delete(id); manager.draft = PromptDraft(); reload(); interface.call("nativeSaved", "")
                }
            case "import", "export":
                modal = true; panel.level = .normal; defer { modal = false; panel.level = .popUpMenu; panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(interface.view) }
                NSApp.activate(ignoringOtherApps: true)
                if let message = try name == "import" ? manager.importFile() : manager.exportFile() { interface.toast(message) }
            case "dismiss": dismiss(restore: true)
            case "insert":
                if let id = payload["id"] as? String, let prompt = store.prompts.first(where: { $0.id.uuidString == id }) { confirm(prompt) }
            case "copy":
                if let body = payload["body"] as? String { copyText(body); interface.toast("正文已复制") }
            default: try settings.handle(name, payload); reload()
            }
        } catch { if name == "save" { interface.call("nativeSaveFailed", "") }; interface.toast(error.localizedDescription); reload() }
    }
    func toggle() { guard !modal, !recording else { return }; panel.isVisible ? dismiss(restore: true) : show() }
    func show(_ destination: String = "resume") {
        guard !busy, !modal else { return }
        if panel.isVisible { reload(); interface.open(destination); panel.makeKeyAndOrderFront(nil); return }
        let caret = insertion.capture(), mouse = NSEvent.mouseLocation
        let point = caret.map { NSPoint(x: $0.minX, y: $0.minY) } ?? mouse
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main!
        let scale = configuration.value.pickerSize.scale
        panel.setFrame(PickerPlacement.frame(caret: caret, mouse: mouse, visibleScreen: screen.visibleFrame, desiredSize: NSSize(width: 480*scale, height: 424*scale)), display: false)
        reload(); interface.open(destination); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(interface.view)
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if let self, !self.modal, event.window !== self.panel { self.dismiss(restore: false) }; return event
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, !self.modal else { return }; self.dismiss(restore: false)
        }) { monitors.append(m) }
    }
    func resize() {
        guard panel.isVisible else { return }
        let scale = configuration.value.pickerSize.scale
        let screen = panel.screen ?? NSScreen.main!
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let width = min(480*scale, area.width), height = min(424*scale, area.height)
        let x = min(max(panel.frame.minX, area.minX), area.maxX-width)
        let y = min(max(panel.frame.maxY-height, area.minY), area.maxY-height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
    func dismiss(restore: Bool) {
        panel.orderOut(nil); monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        recording = false
        if restore { insertion.restore() }
    }
    func canQuit() -> Bool { modal = true; panel.level = .normal; defer { modal = false; panel.level = .popUpMenu }; return manager.canLeave() }
    func reload() {
        var state = settings.state
        state["prompts"] = interfacePrompts(store.search(""))
        state["scale"] = configuration.value.pickerSize.scale
        interface.state = state
    }
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
