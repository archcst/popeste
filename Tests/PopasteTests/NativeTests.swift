import AppKit

@main struct NativeTests {
    static func key(_ chars: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:code)!
    }
    static func main() {
        let editorBounds = CGRect(x: 200, y: 400, width: 600, height: 100)
        let emptyCaret = Insertion.normalizedInsertionBounds(editorBounds, range: CFRange(location: 0, length: 0), empty: true)
        assert(emptyCaret == CGRect(x: 200, y: 400, width: 0, height: 22))
        assert(Insertion.normalizedInsertionBounds(editorBounds, range: CFRange(location: 0, length: 20), empty: false) == editorBounds)
        let exactCaret = CGRect(x: 220, y: 410, width: 0, height: 27)
        assert(Insertion.normalizedInsertionBounds(exactCaret, range: CFRange(location: 0, length: 0), empty: true) == exactCaret)
        _ = NSApplication.shared
        let e = NativeEditor(frame:NSRect(x:0,y:0,width:130,height:300))
        let ew = NSWindow(contentRect:NSRect(x:0,y:0,width:130,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        ew.contentView = e
        e.font = .systemFont(ofSize:17); e.textContainer?.containerSize = NSSize(width:130,height:10000)
        e.allowsUndo = true; e.vimEnabled = true; e.string = "A👨‍👩‍👧‍👦你好\nsecond line"
        e.cursor(0); _ = e.handleVim(key("l")); assert(e.selectedRange().location == 1)
        _ = e.handleVim(key("l")); assert(e.selectedRange().location == 12)
        _ = e.handleVim(key("h")); assert(e.selectedRange().location == 1)
        _ = e.handleVim(key("x")); assert(e.string == "A你好\nsecond line")
        _ = e.handleVim(key("u")); assert(e.string == "A👨‍👩‍👧‍👦你好\nsecond line")
        e.string = "one\ntwo\nthree"; e.cursor(0)
        _ = e.handleVim(key("d")); _ = e.handleVim(key("d")); assert(e.string == "two\nthree")
        _ = e.handleVim(key("p")); assert(e.string == "two\none\nthree")
        _ = e.handleVim(key("i")); assert(!e.normal)
        _ = e.handleVim(key("\u{1b}",code:53)); assert(e.normal)
        e.string = String(repeating:"abcdefghij ",count:20); e.cursor(0); e.moveVisual(1)
        let middle = e.selectedRange().location; assert(middle > 0 && middle < (e.string as NSString).length)
        e.moveVisual(-1); assert(e.selectedRange().location == 0)
        let ui = NativeInterface(mode:"list")
        let w = NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:424),styleMask:.borderless,backing:.buffered,defer:false)
        w.contentView = ui.view
        var events: [String] = []; var savePayload: [String:Any] = [:]
        ui.action = { name,payload in events.append(name); if name == "save" { savePayload = payload } }
        ui.state = ["scale":1.0,"navigationSchemes":["arrows"],"prompts":[["id":"fixture","body":"test body","pinned":false]]]
        ui.open("new")
        let editor = ui.view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NativeEditor }.first!
        editor.string = "unsaved fixture"; ui.textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
        assert(ui.handleKey(key("\u{1b}",code:53)))
        assert(ui.view.subviews.contains { ($0 as? NSTextField)?.stringValue == tr("保存未完成的修改？") })
        _ = ui.handleKey(key("\r",code:36)); assert(savePayload["body"] as? String == "unsaved fixture")
        ui.call("nativeSaveFailed", ""); _ = ui.handleKey(key("\u{1b}",code:53))
        assert(editor.string == "unsaved fixture")
        _ = ui.handleKey(key("\u{1b}",code:53)); _ = ui.handleKey(key("n")); assert(events.contains("discard"))
        ui.open("new"); editor.string = "save fixture"
        ui.textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
        _ = ui.handleKey(key("\u{1b}",code:53)); _ = ui.handleKey(key("\r",code:36))
        ui.call("nativeSaved","fixture")
        assert(ui.view.subviews.contains { $0 is NativeSearch })
        ui.open("list")
        let search = ui.view.subviews.compactMap { $0 as? NativeSearch }.first!
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        w.makeFirstResponder(search); search.stringValue = "no matching fixture"
        search.currentEditor()?.string = "no matching fixture"
        ui.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:search))
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        assert(search.currentEditor() != nil && w.firstResponder === search.currentEditor())
        assert(ui.view.subviews.contains { $0 is NSScrollView })
        let testSearchEditor = search.currentEditor() as! NSTextView
        testSearchEditor.setMarkedText("中文候选",selectedRange:NSRange(location:4,length:0),replacementRange:NSRange(location:0,length:(search.stringValue as NSString).length))
        ui.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:search))
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        assert(testSearchEditor.hasMarkedText())
        assert(!ui.handleKey(key("\r",code:36)))
        testSearchEditor.unmarkText()
        ui.open("settings")
        assert(ui.view.subviews.contains { ($0 as? NativeButton)?.title == tr("完成") })
        var sizeSelection = ""
        ui.action = { name,payload in
            if name == "size" { sizeSelection = payload["value"] as? String ?? ""; ui.state["size"] = sizeSelection }
        }
        for (index, size) in ["small","medium","large"].enumerated() {
            let control = ui.view.subviews.compactMap { $0 as? NSSegmentedControl }.first!
            control.selectedSegment = index
            _ = control.sendAction(control.action!,to:control.target)
            assert(sizeSelection == size)
            assert(ui.view.subviews.compactMap { $0 as? NSSegmentedControl }.first!.selectedSegment == index)
        }
        var toggleValue = false
        let toggle = SettingsToggle("fixture",enabled:false) { toggleValue = $0 }
        toggle.performClick(nil); assert(toggleValue && toggle.state == .on)
        toggle.performClick(nil); assert(!toggleValue && toggle.state == .off)
        let languageControl = ui.view.subviews.compactMap { $0 as? NativeButton }.first { $0.title == tr("跟随系统") }!
        languageControl.invoke?()
        assert(ui.view.subviews.contains { $0 is SettingsMenuShield })
        var languageSelection = ""
        ui.action = { name,payload in if name == "language" { languageSelection = payload["value"] as? String ?? ""; ui.state["language"] = languageSelection } }
        _ = ui.handleKey(key("",code:125)); _ = ui.handleKey(key("",code:125)); _ = ui.handleKey(key("\r",code:36))
        assert(languageSelection == "zh-Hans")
        assert(!ui.view.subviews.contains { $0 is SettingsMenuShield })
        func assertSettingsAlignment(_ scale: CGFloat) {
            for child in ui.view.subviews {
                var isControl = child is NSControl
                if #available(macOS 26.0, *), child is GlassSizeSelector { isControl = true }
                guard isControl else { continue }
                let center = child.frame.midY / scale
                guard center >= 57, center < 372 else { continue }
                let row = floor((center-57)/35)
                assert(abs(center-(57+row*35+17.5)) < 0.01)
            }
        }
        // The same settings state works with and without the native glass surface.
        for scale in [0.8, 0.9, 1.0] {
            ui.state["scale"] = scale
            ui.state["glassStyle"] = "clear"
            ui.state["glass"] = true
            assertSettingsAlignment(scale)
            let glassButton = ui.view.subviews.compactMap { $0 as? NativeButton }.first { $0.title == tr("液态玻璃") }
            assert(glassButton != nil)
            let glassPath = ui.view.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "~/.config/popeste" }!.frame.minY
            for dark in [false, true] {
                ui.state["dark"] = dark
                ui.state["glassStyle"] = "clear"
                let clearOpacity = ui.view.fill.alphaComponent
                assert(abs(clearOpacity - 0.55) < 0.001)
                ui.state["glassStyle"] = "regular"
                assert(ui.view.fill.alphaComponent == 0)
                assert(ui.view.appearance == nil)
            }
            ui.state["glassStyle"] = "clear"
            ui.state["glass"] = false
            assertSettingsAlignment(scale)
            assert(!ui.view.subviews.contains { ($0 as? NativeButton)?.title == tr("液态玻璃") })
            assert(!ui.view.subviews.contains { ($0 as? NSTextField)?.stringValue == tr("玻璃样式") })
            let solidPath = ui.view.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "~/.config/popeste" }!.frame.minY
            assert(abs(glassPath - solidPath - 35 * scale) < 0.01)
            assert(ui.view.fill.alphaComponent == 1)
            assert(ui.view.appearance != nil)
            assert(ui.state["glassStyle"] as? String == "clear")
        }
        if #available(macOS 26.0, *) {
            var pickedSize = -1
            let selector = GlassSizeSelector(labels:["S","M","L"],selected:0,scale:1) { pickedSize = $0 }
            selector.frame = NSRect(x:0,y:0,width:114,height:30)
            w.contentView?.addSubview(selector)
            selector.layoutSubtreeIfNeeded()
            let glass = selector.subviews.compactMap { $0 as? NSGlassEffectView }.first!
            assert(glass.contentView?.subviews.contains { ($0 as? NativeButton)?.title == "S" } == true)
            assert(glass.contentView!.subviews.first!.frame == glass.contentView!.bounds)
            selector.select(2)
            RunLoop.current.run(until:Date().addingTimeInterval(0.35))
            assert(selector.selectedIndex == 2 && pickedSize == 2)
            assert(glass.contentView?.subviews.contains { ($0 as? NativeButton)?.title == "L" } == true)
            selector.removeFromSuperview()
        }
        // Horizontal navigation changes scope, never opens the detail page.
        let tagUI = NativeInterface(mode: "list")
        let tagWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:424),styleMask:.borderless,backing:.buffered,defer:false)
        tagWindow.contentView = tagUI.view
        tagUI.state = ["prompts":[
            ["id":"a","body":"Alpha","tags":["Work"],"lastUsed":10.0],
            ["id":"b","body":"Beta","tags":["Work"],"lastUsed":20.0],
            ["id":"c","body":"Gamma","tags":[]]
        ]]
        var selectedID = ""
        var draftTags: [String] = []
        tagUI.action = { name,payload in
            if name == "insert" { selectedID = payload["id"] as? String ?? "" }
            if name == "save" { draftTags = payload["tags"] as? [String] ?? [] }
        }
        assert(tagUI.handleKey(key("",code:124))) // Recent, expanded directly.
        assert(tagUI.handleKey(key("",code:36)))
        assert(selectedID == "b")
        assert(tagUI.handleKey(key("",code:124))) // Work.
        assert(tagUI.handleKey(key("",code:36)))
        assert(selectedID == "a")
        assert(tagUI.handleKey(key("",code:125)))
        assert(tagUI.handleKey(key("",code:36)))
        assert(selectedID == "b")
        tagUI.open("edit")
        let tagInput = tagUI.view.subviews.compactMap { $0 as? NSTextField }.first { $0.placeholderString == tr("用逗号分隔标签") }!
        assert(tagInput.stringValue == "Work")
        tagInput.stringValue = "Work, Personal, Work"
        assert(tagUI.handleKey(key("s",code:1,flags:.command)))
        assert(draftTags == ["Work", "Personal"])

        let savedLanguage = AppText.language
        for language in Preferences.supportedLanguages {
            AppText.language = { language }
            for scale in [0.8, 0.9, 1.0] {
                for schemes in [["arrows"], ["emacs"], ["vim"], ["arrows","emacs","vim"], []] {
                    let searchUI = NativeInterface(mode:"list")
                    searchUI.view.frame = NSRect(x:0,y:0,width:480*scale,height:57*scale)
                    searchUI.state = ["scale":scale,"navigationSchemes":schemes,"prompts":[]]
                    searchUI.view.layoutSubtreeIfNeeded()
                    let hint = searchUI.view.subviews.compactMap { $0 as? NativeLabel }.first!
                    let input = searchUI.view.subviews.compactMap { $0 as? NativeSearch }.first!
                    assert(hint.frame.width >= hint.intrinsicContentSize.width)
                    assert(hint.frame.minX > input.frame.maxX)
                    assert(hint.frame.maxX <= searchUI.view.bounds.width)
                }
            }
        }
        AppText.language = savedLanguage
        // Exercise the real fallback wrapper without changing system preferences.
        let priorGlassOverride = ProcessInfo.processInfo.environment["POPASTE_GLASS"]
        setenv("POPASTE_GLASS", "0", 1)
        let surface = GlassSurface(frame:NSRect(x:0,y:0,width:480,height:424))
        let content = NSView(frame:surface.bounds)
        surface.install(content)
        surface.update(scale:1,dark:false,style:"clear")
        assert(!surface.glassEnabled && content.superview === surface)
        assert(surface.layer?.masksToBounds == true)
        if let priorGlassOverride { setenv("POPASTE_GLASS", priorGlassOverride, 1) }
        else { unsetenv("POPASTE_GLASS") }
        print("Glass availability, compact fallback settings, and opaque surface checks passed")
        print("Native editor, TextKit wrapping, search focus / marked text, and save-confirmation checks passed")
    }
}
