import AppKit

@main struct PopasteApp {
    static func main() { let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run(); withExtendedLifetime(delegate) {} }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: Store!; var picker: Picker!; var manager: Manager!; var settings: Settings!; var status: NSStatusItem!; var hotKey: HotKey!; var configuration: Configuration!
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { configuration = try Configuration(); store = try Store(); hotKey = HotKey(configuration: configuration) } catch { showError(error); NSApp.terminate(nil); return }
        picker = Picker(store: store, configuration: configuration); manager = Manager(store: store, configuration: configuration); settings = Settings(hotKey: hotKey, configuration: configuration)
        manager.settingsAction = { [weak self] in self?.settings.show() }; settings.back = { [weak self] in self?.manager.show() }; picker.settings = { [weak self] in self?.settings.show() }
        picker.create = { [weak self] in self?.manager.show(); self?.manager.create() }; settings.importAction = { [weak self] in self?.manager.show(); self?.manager.importFile() }
        picker.manage = { [weak self] in self?.manager.show() }; hotKey.action = { [weak self] in self?.picker.toggle() }
        store.onChange = { [weak self] in self?.picker.reload() }
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "Popaste")
        for (title, selector, key) in [("管理提示词…", #selector(manage), "1"), ("设置…", #selector(preferences), ","), ("呼出提示词", #selector(toggle), "2"), ("退出 Popaste", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; appMenu.addItem(item)
        }
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength); status.button?.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Popaste")
        let menu = NSMenu()
        for (name, action) in [("呼出提示词", #selector(toggle)), ("管理提示词…", #selector(manage)), ("设置…", #selector(preferences)), ("退出 Popaste", #selector(quit))] { let item = NSMenuItem(title: name, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }; status.menu = menu
        do { try hotKey.register(hotKey.shortcut) } catch { showError(error); settings.show() }
        if !configuration.value.onboarded { settings.show(); do { try configuration.update { $0.onboarded = true } } catch { showError(error) } } else { manager.show() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { manager.show() }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { manager == nil || manager.canLeave() ? .terminateNow : .terminateCancel }
    @objc func toggle() { picker.toggle() }
    @objc func manage() { picker.dismiss(restore: false); manager.show() }
    @objc func preferences() { picker.dismiss(restore: false); settings.show() }
    @objc func quit() { NSApp.terminate(nil) }
}
