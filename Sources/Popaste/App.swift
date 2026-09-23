import AppKit

@main struct PopasteApp {
    static func main() { let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run(); withExtendedLifetime(delegate) {} }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: Store!; var picker: Picker!; var settings: Settings!; var status: NSStatusItem!; var hotKey: HotKey!; var configuration: Configuration!
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { configuration = try Configuration(); store = try Store(); hotKey = HotKey(configuration: configuration) } catch { showError(error); NSApp.terminate(nil); return }
        AppText.language = { [weak self] in self?.configuration.value.resolvedLanguage ?? "zh-Hans" }
        settings = Settings(hotKey: hotKey, configuration: configuration)
        picker = Picker(store: store, configuration: configuration, settings: settings)
        picker.preferencesChanged = { [weak self] in self?.localizeMenus() }
        hotKey.action = { [weak self] in self?.picker.toggle() }
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "Popaste")
        for (title, selector, key) in [("新建提示词", #selector(newPrompt), "n"), ("编辑所选提示词", #selector(editPrompt), "e"), ("管理提示词…", #selector(manage), "1"), ("设置…", #selector(preferences), ","), ("呼出提示词", #selector(toggle), "2"), ("退出 Popaste", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.representedObject = title; item.target = self; appMenu.addItem(item)
        }
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.representedObject = title; editMenu.addItem(item)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); status.button?.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Popaste")
        let menu = NSMenu()
        for (name, action) in [("呼出提示词", #selector(toggle)), ("新建提示词", #selector(newPrompt)), ("管理提示词…", #selector(manage)), ("设置…", #selector(preferences)), ("退出 Popaste", #selector(quit))] { let item = NSMenuItem(title: name, action: action, keyEquivalent: ""); item.representedObject = name; item.target = self; menu.addItem(item) }; status.menu = menu
        localizeMenus()
        do { try hotKey.register(hotKey.shortcut) } catch { showError(error); picker.show("settings") }
        if !configuration.value.onboarded { picker.show("settings"); do { try configuration.update { $0.onboarded = true } } catch { showError(error) } } else { picker.show("list") }
    }
    private func localizeMenus() {
        func update(_ menu: NSMenu?) {
            guard let menu else { return }
            if menu.title == "编辑" || menu.title == "Edit" { menu.title = tr("编辑") }
            for item in menu.items {
                if let source = item.representedObject as? String { item.title = tr(source) }
                update(item.submenu)
            }
        }
        update(NSApp.mainMenu); update(status?.menu)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !picker.panel.isVisible { picker.show() }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { picker == nil || picker.canQuit() ? .terminateNow : .terminateCancel }
    @objc func toggle() { picker.toggle() }
    @objc func manage() { picker.show("list") }
    @objc func newPrompt() { picker.show("new") }
    @objc func editPrompt() { picker.show("edit") }
    @objc func preferences() { picker.show("settings") }
    @objc func quit() { NSApp.terminate(nil) }
}
