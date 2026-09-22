import AppKit
import UniformTypeIdentifiers

final class Manager: NSObject, NSWindowDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    let search = NSSearchField(); let body = NSTextView(); let pinned = NSButton(checkboxWithTitle: "置顶", target: nil, action: nil)
    let status = label("", secondary: true); let store: Store
    var editing: Prompt?; var rows: [Prompt] = []; var changing = false
    let interface = WebInterface(mode: "manager")
    let configuration: Configuration
    init(store: Store, configuration: Configuration) {
        self.store = store; self.configuration = configuration; super.init()
        window.title = "Popaste · 提示词管理"; window.delegate = self; interface.attach(to: window)
        interface.action = { [weak self] name, payload in self?.handle(name, payload) }
        rows = store.search(""); load(rows.first); refresh()
    }
    private func handle(_ name: String, _ payload: [String: Any]) {
        switch name {
        case "ready", "refresh": sync()
        case "draft": body.string = payload["body"] as? String ?? body.string; status.stringValue = "有未保存的修改"
        case "select":
            guard let id = payload["id"] as? String, let prompt = store.prompts.first(where: { $0.id.uuidString == id }), prompt.id != editing?.id, canLeave() else { return }
            load(prompt); refresh()
        case "new": create()
        case "save": body.string = payload["body"] as? String ?? body.string; save()
        case "cancel": cancel(); sync()
        case "pin": pinned.state = pinned.state == .on ? .off : .on; status.stringValue = "有未保存的修改"; sync()
        case "delete": remove()
        case "copy": copyText(payload["body"] as? String ?? body.string); interface.toast("正文已复制")
        case "import": importFile()
        case "export": exportFile()
        case "settings": openSettings()
        case "search": search.stringValue = payload["query"] as? String ?? ""; refresh()
        default: break
        }
    }
    private func sync() {
        interface.state = ["prompts": interfacePrompts(rows), "selectedID": editing?.id.uuidString ?? "", "body": body.string, "pinned": pinned.state == .on, "status": status.stringValue, "dark": interfaceDark(configuration.value.appearance ?? "system")]
    }
    var settingsAction: (() -> Void)?
    @objc func openSettings() { settingsAction?() }
    func controlTextDidChange(_ notification: Notification) { refresh() }
    func show() { sync(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(interface.view) }
    func refresh() { rows = store.search(search.stringValue); sync() }
    var dirty: Bool { body.string != (editing?.body ?? "") || (pinned.state == .on) != (editing?.pinned ?? false) }
    func canLeave() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "保存未完成的修改？"; alert.informativeText = "离开前可以保存，或放弃当前修改。"; alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "继续编辑"); alert.addButton(withTitle: "放弃修改")
        let result = alert.runModal(); if result == .alertFirstButtonReturn { return persist() }; return result == .alertThirdButtonReturn
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { guard canLeave() else { return false }; load(editing); return true }
    func load(_ p: Prompt?) { editing = p; body.string = p?.body ?? ""; body.undoManager?.removeAllActions(); pinned.state = p?.pinned == true ? .on : .off; status.stringValue = p == nil ? "输入你想保存的提示词。" : "已保存到本机。"; sync() }
    @objc func create() { guard canLeave() else { return }; load(nil); window.makeFirstResponder(interface.view); interface.view.evaluateJavaScript("window.nativeFocusEditor()", completionHandler: nil) }
    @discardableResult func persist() -> Bool {
        guard !body.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status.stringValue = "请填写正文。"; sync(); window.makeFirstResponder(interface.view); return false }
        var p = editing ?? Prompt(body: ""); p.body = body.string; p.pinned = pinned.state == .on; p.updated = Date()
        do { try store.save(p); load(p); refresh(); status.stringValue = "已保存到本机"; sync(); return true } catch { showError(error); return false }
    }
    @objc func save() { persist() }
    @objc func cancel() { if canDiscard() { load(editing) } }
    func canDiscard() -> Bool { guard dirty else { return true }; let a = NSAlert(); a.messageText = "放弃未保存的修改？"; a.addButton(withTitle: "继续编辑"); a.addButton(withTitle: "放弃修改"); return a.runModal() == .alertSecondButtonReturn }
    @objc func remove() {
        guard let p = editing else { return }; let a = NSAlert(); a.messageText = "删除这条提示词？"; a.informativeText = "此操作会删除已保存内容及当前编辑草稿。"; a.addButton(withTitle: "取消"); a.addButton(withTitle: "删除")
        if a.runModal() == .alertSecondButtonReturn { do { try store.delete(p.id); load(nil); refresh(); status.stringValue = "已删除。"; sync() } catch { showError(error) } }
    }
    @objc func copyBody() { copyText(body.string); status.stringValue = "正文已复制。" }
    @objc func importFile() {
        guard canLeave() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let (values, summary) = store.planImport(try Store.decode(Data(contentsOf: url)))
            let a = NSAlert(); a.messageText = "导入预览"; a.informativeText = "新增 \(summary.added) 条。\n跳过正文完全相同的 \(summary.duplicate) 条。现有内容不会被覆盖。"; a.addButton(withTitle: "导入"); a.addButton(withTitle: "取消")
            if a.runModal() == .alertFirstButtonReturn { try store.commit(values); refresh(); status.stringValue = "导入完成：新增 \(summary.added) 条，跳过 \(summary.duplicate) 条。"; sync() }
        } catch { showError(error) }
    }
    @objc func exportFile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Popaste-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(to: url); status.stringValue = "已导出所有已保存提示词。"; sync() } catch { showError(error) }
    }
}
