import AppKit

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // The native interface owns cancellation and draft confirmation.
    var keyHandler: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown && keyHandler?(event) == true { return }; super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) {}
}
final class Picker: NSObject, NSWindowDelegate {
    let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 424), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
    private let surface = GlassSurface()
    let store: Store
    let configuration: Configuration
    let settings: Settings
    let manager: Manager
    let interface = NativeInterface(mode: "list")
    let insertion = Insertion()
    private var monitors: [Any] = []
    var preferencesChanged: (() -> Void)?
    private var activationObserver: NSObjectProtocol?
    private var busy = false
    private var pendingInsertions: [Prompt] = []
    private var insertionFocusRevision = 0
    private(set) var windowPinned = false
    private var modal = false
    private var recording = false
    private var collapsed = false
    private var savingWindowSize = false
    private var minimumExpandedHeight: CGFloat = 140
    private var expansionAnchor = NSRect.zero
    private var currentPage = "list"
    init(store: Store, configuration: Configuration, settings: Settings) {
        self.store = store; self.configuration = configuration; self.settings = settings
        manager = Manager(store: store)
        super.init()
        panel.delegate = self
        panel.keyHandler = { [weak self] in self?.interface.handleKey($0) ?? false }
        panel.hidesOnDeactivate = false
        panel.title = "Popaste"; panel.level = .popUpMenu; panel.hasShadow = true; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.isReleasedWhenClosed = false
        surface.frame = panel.contentView!.bounds
        surface.autoresizingMask = [.width, .height]
        surface.install(interface.view)
        panel.contentView = surface
        interface.action = { [weak self] name, payload in self?.handle(name, payload) }
        store.onChange = { [weak self] in self?.reload() }
        configuration.onChange = { [weak self] in self?.resize(); self?.reload(); self?.preferencesChanged?() }
        // A nonactivating panel can keep the original app active, so Cmd+Tab also
        // needs a workspace activation observer rather than only app deactivation.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, !self.modal, self.panel.isVisible,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            if self.windowPinned {
                // Activating the insertion target is part of a paste, not a user switch.
                if self.busy && app.processIdentifier == self.insertion.target?.processIdentifier { return }
                self.insertionFocusRevision += 1
                self.pendingInsertions.removeAll()
                _ = self.insertion.capture()
            }
            else { self.dismiss(restore: false) }
        }
    }
    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }
    func windowDidResignKey(_ notification: Notification) {
        guard !modal else { return }
        // Let temporary responder changes settle before deciding whether focus left.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.modal, self.panel.isVisible, !self.panel.isKeyWindow, self.interface.tagColorPickerWindow == nil else { return }
            self.dismiss(restore: false)
        }
    }
    private func handle(_ name: String, _ payload: [String: Any]) {
        do {
            switch name {
            case "ready", "refresh": reload()
            case "layout":
                currentPage = payload["page"] as? String ?? "list"
                minimumExpandedHeight = payload["minimumHeight"] as? CGFloat ?? (currentPage == "list" ? 140 : 424)
                collapsed = currentPage == "list" && payload["collapsed"] as? Bool == true
                resize()
            case "recording": recording = payload["enabled"] as? Bool ?? false
            case "draft": manager.receive(payload)
            case "discard": manager.draft = PromptDraft()
            case "save":
                manager.receive(payload)
                let prompt = try manager.save(); reload(); interface.call("nativeSaved", prompt.id.uuidString)
            case "updateTag":
                if let old = payload["old"] as? String, let name = payload["name"] as? String, let color = payload["color"] as? String {
                    if old != name { try store.renameTag(old,to:name) }
                    try configuration.update {
                        let visible = payload["visible"] as? Bool ?? !($0.hiddenTags ?? []).contains { $0.lowercased() == old.lowercased() }
                        $0.setTagVisibility(name,visible:visible,replacing:old)
                        if let order = $0.tagOrder { $0.tagOrder = Prompt.normalizedTags(order.map { $0.lowercased() == old.lowercased() ? name : $0 }) }
                        if $0.tagColors == nil { $0.tagColors = [:] }
                        $0.tagColors?[old.lowercased()] = nil; $0.tagColors?[name.lowercased()] = color.isEmpty ? nil : color
                    }
                    interface.call("nativeTagRenamed",name); reload()
                }
            case "deleteTag":
                if let name = payload["name"] as? String {
                    try store.deleteTag(name)
                    try configuration.update { $0.setTagVisibility(name,visible:true) }
                    if let order = configuration.value.tagOrder {
                        try configuration.update { $0.tagOrder = order.filter { $0.lowercased() != name.lowercased() } }
                    }
                    if configuration.value.tagColors?[name.lowercased()] != nil { try configuration.update { $0.tagColors?[name.lowercased()] = nil } }
                    interface.call("nativeTagRenamed", ""); reload()
                }
            case "delete":
                if let id = (payload["id"] as? String).flatMap(UUID.init(uuidString:)) {
                    try store.delete(id); manager.draft = PromptDraft(); reload(); interface.call("nativeSaved", "")
                }
            case "toggleWindowPin":
                windowPinned.toggle(); pendingInsertions.removeAll(); reload()
            case "dismiss": dismiss(restore: true, explicit: payload["explicit"] as? Bool == true)
            case "insert":
                if let id = payload["id"] as? String, let prompt = store.prompts.first(where: { $0.id.uuidString == id }) { confirm(prompt, continuous:payload["continuous"] as? Bool == true) }
            case "copy":
                if let body = payload["body"] as? String { copyText(body); interface.toast(tr("正文已复制")) }
            default: try settings.handle(name, payload); reload()
            }
        } catch { if name == "save" { interface.call("nativeSaveFailed", "") }; interface.toast(error.localizedDescription); reload() }
    }
    func toggle() { guard !modal, !recording else { return }; panel.isVisible ? dismiss(restore: true) : show() }
    func show(_ destination: String = "resume") {
        guard !busy, !modal else { return }
        if panel.isVisible { reload(); interface.open(destination); panel.makeKeyAndOrderFront(nil); return }
        collapsed = false
        let caret = insertion.capture(), mouse = NSEvent.mouseLocation
        let point = caret.map { NSPoint(x: $0.minX, y: $0.minY) } ?? mouse
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main!
        let scale = configuration.value.pickerSize.scale
        // Position the visible search bar itself; expansion handles screen edges later.
        let frame = PickerPlacement.frame(caret: caret, mouse: mouse, visibleScreen: screen.visibleFrame, desiredSize: desiredWindowSize)
        expansionAnchor = NSRect(x: frame.minX, y: frame.maxY - 57*scale, width: frame.width, height: 57*scale)
        updateResizeLimits()
        panel.setFrame(frame, display: false)
        reload(); interface.open(destination); panel.makeKeyAndOrderFront(nil); interface.focus()
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if let self, !self.modal, event.window !== self.panel, event.window !== self.interface.tagColorPickerWindow { self.dismiss(restore: false) }; return event
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, !self.modal else { return }
            if self.windowPinned {
                self.insertionFocusRevision += 1
                self.pendingInsertions.removeAll()
                // Read the focused control after the click has reached the other app.
                DispatchQueue.main.asyncAfter(deadline:.now()+0.05) { [weak self] in
                    guard let self, self.windowPinned, !self.panel.isKeyWindow,
                          NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                    _ = self.insertion.capture()
                }
            } else { self.dismiss(restore: false) }
        }) { monitors.append(m) }
    }
    private var desiredWindowSize: NSSize {
        let scale = configuration.value.pickerSize.scale
        let dimensions = configuration.value.resolvedPickerDimensions
        return NSSize(width:dimensions.width*scale,height:(collapsed ? 57 : max(minimumExpandedHeight,dimensions.height))*scale)
    }
    private func updateResizeLimits() {
        let scale = configuration.value.pickerSize.scale
        panel.contentMinSize = NSSize(width:480*scale,height:(collapsed ? 57 : minimumExpandedHeight)*scale)
        panel.contentMaxSize = NSSize(width:1600*scale,height:(collapsed ? 57 : 1400)*scale)
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let scale = configuration.value.pickerSize.scale
        return NSSize(width:max(480*scale,min(1600*scale,frameSize.width)),height:collapsed ? 57*scale : max(minimumExpandedHeight*scale,min(1400*scale,frameSize.height)))
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        let scale = configuration.value.pickerSize.scale
        let old = configuration.value.resolvedPickerDimensions
        let height = panel.frame.height/scale
        let preserveHeight = collapsed || (minimumExpandedHeight > 140 && old.height < minimumExpandedHeight && height <= minimumExpandedHeight)
        let size = PickerDimensions(width:panel.frame.width/scale,height:preserveHeight ? old.height : height).constrained
        expansionAnchor = NSRect(x:panel.frame.minX,y:panel.frame.maxY-57*scale,width:panel.frame.width,height:57*scale)
        guard size != old else { return }
        savingWindowSize = true
        defer { savingWindowSize = false }
        do { try configuration.update { $0.pickerDimensions = size } }
        catch { interface.toast(error.localizedDescription) }
    }
    func resize() {
        updateResizeLimits()
        guard panel.isVisible, !panel.inLiveResize, !savingWindowSize else { return }
        let screen = panel.screen ?? NSScreen.main!
        let frame = PickerPlacement.resizedFrame(expansionAnchor, visibleScreen: screen.visibleFrame,
            desiredSize: desiredWindowSize)
        panel.setFrame(frame, display: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !windowPinned }
    func dismiss(restore: Bool, explicit: Bool = false) {
        guard explicit || !windowPinned else { return }
        pendingInsertions.removeAll()
        insertionFocusRevision += 1
        interface.closeTagColorPicker()
        panel.orderOut(nil); monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        recording = false
        if restore { insertion.restore() }
    }
    func canQuit() -> Bool { guard !windowPinned else { return false }; modal = true; panel.level = .normal; defer { modal = false; panel.level = .popUpMenu }; return manager.canLeave() }
    func reload() {
        surface.update(scale: configuration.value.pickerSize.scale, dark: interfaceDark(configuration.value.appearance ?? "system"), style: configuration.value.resolvedGlassStyle)
        panel.invalidateShadow()
        var state = settings.state
        state["prompts"] = interfacePrompts(store.search(""))
        state["scale"] = configuration.value.pickerSize.scale
        state["glass"] = surface.glassEnabled
        state["windowPinned"] = windowPinned
        interface.state = state
    }
    private func confirm(_ prompt: Prompt, continuous: Bool = false) {
        guard panel.isVisible else { return }
        if busy { if continuous { pendingInsertions.append(prompt) }; return }
        busy = true
        if !continuous { dismiss(restore:false,explicit:true) }
        let focusRevision = insertionFocusRevision
        let targetPID = insertion.target?.processIdentifier
        insertion.paste(prompt.body, keepingFocus: continuous) { [weak self] success in
            guard let self else { return }; self.busy = false
            if success {
                do { try self.store.used(prompt.id) } catch { showError(error) }
                if continuous, self.panel.isVisible, self.insertionFocusRevision == focusRevision,
                   NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID {
                    if !self.pendingInsertions.isEmpty {
                        let next = self.pendingInsertions.removeFirst()
                        self.confirm(next, continuous:true)
                    }
                }
            }
            else {
                self.pendingInsertions.removeAll()
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert(); alert.messageText = tr("无法自动插入"); alert.informativeText = tr("请检查辅助功能权限，并保持原输入窗口可用。你可以复制正文后手动粘贴。"); alert.addButton(withTitle: tr("复制正文")); alert.addButton(withTitle: tr("取消"))
                if alert.runModal() == .alertFirstButtonReturn { copyText(prompt.body) }
            }
        }
    }
}
