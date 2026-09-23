import AppKit

/// The panel's entire interface is native AppKit. It shares the existing persistence actions.
final class NativeInterface: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
    let view = NativeCanvas()
    var action: ((String, [String: Any]) -> Void)?
    var state: [String: Any] = [:] { didSet { applyState() } }
    private let search = NativeSearch()
    private let editor = NativeEditor()
    private let scroll = NSScrollView()
    private let rows = NativeCanvas()
    private var parts: [(NSView, CGRect)] = []
    private var page = "list", query = ""
    private var expanded = false, selected = 0, recording = false
    private var editing: [String: Any]?
    private var pinned = false
    private var dialog: String?
    private var leaveAction: (() -> Void)?
    private var afterSave: (() -> Void)?
    private var saving = false
    private var meta: NSTextField?
    private var saveState: NSTextField?
    private var modeLabel: NSTextField?
    private var countLabel: NSTextField?
    private struct SettingMenu {
        var name: String
        var options: [(String,String)]
        var y: CGFloat
        var multiple: Bool
    }
    private var settingMenu: SettingMenu?
    private var menuSelection = 0
    private var toastGeneration = 0
    private var s: CGFloat { CGFloat(state["scale"] as? Double ?? 1) }
    private var schemes: [String] { state["navigationSchemes"] as? [String] ?? ["arrows"] }
    private var prompts: [[String: Any]] { state["prompts"] as? [[String: Any]] ?? [] }
    private var matches: [[String: Any]] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return prompts.filter { p in terms.allSatisfy { (p["body"] as? String ?? "").localizedCaseInsensitiveContains($0) } }
    }
    private var chosen: [String: Any]? { matches.indices.contains(selected) ? matches[selected] : nil }
    private var dirty: Bool { page == "editor" && (editor.string != (editing?["body"] as? String ?? "") || pinned != (editing?["pinned"] as? Bool ?? false)) }
    init(mode: String) {
        super.init()
        view.autoresizingMask = [.width,.height]
        view.layoutContent = { [weak self] in self?.layout() }
        view.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        search.delegate = self; search.isBordered = false; search.drawsBackground = false; search.focusRingType = .none
        search.setAccessibilityLabel(tr("搜索短语"))
        search.route = { [weak self] in self?.handleKey($0) ?? false }
        editor.delegate = self; editor.isRichText = false; editor.allowsUndo = true; editor.drawsBackground = false
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false; editor.isContinuousSpellCheckingEnabled = false
        editor.textContainerInset = .zero; editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.route = { [weak self] in self?.handleKey($0) ?? false }
        editor.modeChanged = { [weak self] in self?.updateMeta() }
        scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    }
    private func emit(_ name: String, _ payload: [String: Any] = [:]) { action?(name,payload) }
    private func applyState() {
        let oldID = chosen?["id"] as? String
        view.appearance = NSAppearance(named: (state["dark"] as? Bool == true) ? .darkAqua : .aqua)
        if let oldID, let i = matches.firstIndex(where: { $0["id"] as? String == oldID }) { selected = i }
        editor.vimEnabled = page == "editor" && state["vimEditing"] as? Bool == true
        render()
    }
    private func sync() { emit("layout",["page":page,"collapsed":page == "list" && !expanded]) }
    func focus() { view.window?.makeFirstResponder(page == "list" ? search : page == "editor" ? editor : view) }
    func open(_ destination: String = "resume") {
        if dialog != nil && destination != "resume" { return }
        if (search.currentEditor() as? NSTextView)?.hasMarkedText() == true || editor.hasMarkedText() { return }
        if recording && ["new","edit","settings"].contains(destination) { return }
        recording = false; emit("recording",["enabled":false])
        switch destination {
        case "new": edit(nil)
        case "edit": if page == "list" || page == "preview", let chosen { edit(chosen) }
        case "settings": navigate { self.show("settings") }
        case "list": navigate { self.query = ""; self.search.stringValue = ""; self.expanded = false; self.show("list", expand: false) }
        default:
            if page == "list" { query = ""; search.stringValue = ""; selected = 0; expanded = false; sync(); render() }
        }
        DispatchQueue.main.async { [weak self] in self?.focus() }
    }
    func call(_ name: String, _ argument: Any) {
        if name == "nativeSaveFailed" { saving = false; afterSave = nil; return }
        guard name == "nativeSaved" else { return }
        let next = afterSave; saving = false; afterSave = nil; dialog = nil; leaveAction = nil
        editing = nil; query = ""; search.stringValue = ""
        selected = max(0,matches.firstIndex(where: { $0["id"] as? String == argument as? String }) ?? 0)
        if let next { next() } else { show("list") }
        toast(tr((argument as? String)?.isEmpty == false ? "已保存" : "已删除"))
    }
    private func show(_ next: String, expand: Bool = true) {
        if page == "editor" { emit("discard") }
        settingMenu = nil
        page = next; if next == "list" { expanded = expand }
        recording = false; emit("recording",["enabled":false]); sync(); render(); focus()
    }
    private func navigate(_ next: @escaping () -> Void) {
        if dirty { leaveAction = next; dialog = "unsaved"; render(); view.window?.makeFirstResponder(view) } else { next() }
    }
    private func edit(_ phrase: [String: Any]?) {
        let offset = page == "preview" ? scroll.contentView.bounds.origin : .zero
        navigate {
            self.show("editor"); self.editing = phrase; self.pinned = phrase?["pinned"] as? Bool ?? false
            self.editor.string = phrase?["body"] as? String ?? ""; self.editor.undoManager?.removeAllActions()
            self.editor.vimEnabled = self.state["vimEditing"] as? Bool ?? false
            self.editor.normal = self.editor.vimEnabled; self.editor.resetCommand(); self.editor.setSelectedRange(NSRange(location:0,length:0))
            self.render(); self.updateDraft(); self.focus(); self.scroll.contentView.scroll(to: offset)
        }
    }
    private func preview() {
        guard let chosen else { return }; editor.string = chosen["body"] as? String ?? ""
        show("preview"); scroll.contentView.scroll(to: .zero)
    }
    private func updateDraft() { emit("draft",["id":editing?["id"] as? String ?? "","body":editor.string,"pinned":pinned]); updateMeta() }
    private func updateMeta() {
        meta?.stringValue = "\(editor.string.count)"+tr(" 字符")
        saveState?.stringValue = tr(dirty ? "未保存" : "已保存")
        if let modeLabel, let index = parts.firstIndex(where: { $0.0 === modeLabel }) {
            parts[index].1.origin.x = 26+textWidth(meta?.stringValue ?? "",size:10)
            modeLabel.frame.origin.x = parts[index].1.origin.x*s
        }
        modeLabel?.stringValue = editor.vimEnabled ? "Vim · "+tr(editor.normal ? "普通模式" : "插入模式") : ""
    }
    private func save() {
        guard !saving else { return }
        guard !editor.string.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { toast(tr("请输入短语正文")); return }
        saving = true; emit("save",["id":editing?["id"] as? String ?? "","body":editor.string,"pinned":pinned])
    }
    func controlTextDidChange(_ obj: Notification) {
        // An IME can deliver its final text-change notification before unmarking.
        DispatchQueue.main.async { [weak self] in
            guard let self, (self.search.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            self.query = self.search.stringValue; self.selected = 0
            if !self.query.isEmpty { self.expanded = true }
            self.sync(); self.renderRows()
        }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText(), let event = NSApp.currentEvent else { return false }; return handleKey(event)
    }
    func textDidChange(_ notification: Notification) { updateDraft() }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText(), let event = NSApp.currentEvent else { return false }; return handleKey(event)
    }
    private func nav(_ event: NSEvent, _ direction: String) -> Bool {
        let flags = event.modifierFlags.intersection([.control,.command,.option,.shift])
        let keys: [String: UInt16] = ["down":125,"up":126,"back":123,"forward":124]
        if schemes.contains("arrows"), flags.isEmpty, event.keyCode == keys[direction] { return true }
        let chars = event.charactersIgnoringModifiers?.lowercased()
        return flags == .control && ((schemes.contains("emacs") && chars == ["down":"n","up":"p","back":"b","forward":"f"][direction]) || (schemes.contains("vim") && chars == ["down":"j","up":"k","back":"h","forward":"l"][direction]))
    }
    private func navLabel(_ direction: String) -> String {
        schemes.map { $0 == "arrows" ? (direction == "down" ? "↓" : "←") : "⌃"+($0 == "emacs" ? (direction == "down" ? "N" : "B") : (direction == "down" ? "J" : "H")) }.joined(separator:" / ")
    }
    func handleKey(_ event: NSEvent) -> Bool {
        if (search.currentEditor() as? NSTextView)?.hasMarkedText() == true || (page == "editor" && editor.hasMarkedText()) { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? "", flags = event.modifierFlags.intersection([.command,.control,.option,.shift])
        if settingMenu != nil && dialog == nil {
            if event.keyCode == 53 { settingMenu = nil; render(); return true }
            if event.keyCode == 125 || event.keyCode == 126 {
                menuSelection = max(0,min((settingMenu?.options.count ?? 1)-1,menuSelection+(event.keyCode == 125 ? 1 : -1))); render(); return true
            }
            if event.keyCode == 36 { chooseMenuItem(menuSelection); return true }
            if event.keyCode == 48 { settingMenu = nil; render(); return true }
        }
        if dialog != nil {
            if event.keyCode == 53 { closeDialog() }
            else if event.keyCode == 36 { acceptDialog() }
            else if dialog == "unsaved" && key == "n" && flags.isEmpty { let next = leaveAction; closeDialog(); next?() }
            else if event.keyCode == 48 { if flags.contains(.shift) { view.window?.selectPreviousKeyView(nil) } else { view.window?.selectNextKeyView(nil) } }
            return true
        }
        if recording {
            if event.keyCode == 53 { recording = false; emit("recording",["enabled":false]); render(); return true }
            guard !flags.intersection([.control,.option,.command]).isEmpty else { return true }
            emit("nativeShortcut",["keyCode":Int(event.keyCode),"characters":event.charactersIgnoringModifiers ?? "","flags":flags.rawValue])
            recording = false; emit("recording",["enabled":false]); render(); return true
        }
        if flags == .command {
            if key == "n" { edit(nil); return true }
            if key == "," { navigate { self.show("settings") }; return true }
            if key == "e", page == "list" || page == "preview" { if let chosen { edit(chosen) }; return true }
            if key == "s", page == "editor" { save(); return true }
        }
        if page == "editor", editor.vimEnabled && !editor.normal && event.keyCode == 53 { return false }
        if event.keyCode == 53 { if page == "list" { emit("dismiss") } else { navigate { self.show("list") } }; return true }
        if page == "preview" {
            if nav(event,"back") { show("list"); return true }
            if event.keyCode == 36 { insert(); return true }
        }
        if page == "list" {
            if !expanded && (event.keyCode == 36 || nav(event,"down") || nav(event,"up") || nav(event,"forward")) { expanded = true; selected = 0; sync(); render(); focus(); return true }
            if nav(event,"down") || nav(event,"up") { selected += nav(event,"down") ? 1 : -1; renderRows(); return true }
            if nav(event,"forward") { preview(); return true }
            if event.keyCode == 36 { insert(); return true }
            if flags == [.command,.shift] && key == "c", let body = chosen?["body"] { emit("copy",["body":body]); return true }
        }
        return false
    }
    private func insert() { if let id = chosen?["id"] { emit("insert",["id":id]) } }
    private func closeDialog() { guard !saving else { return }; dialog = nil; leaveAction = nil; afterSave = nil; render(); focus() }
    private func acceptDialog() {
        if dialog == "unsaved" { afterSave = leaveAction; save() }
        else if let id = editing?["id"] { dialog = nil; emit("delete",["id":id]) }
    }
    @discardableResult private func add(_ child: NSView, _ rect: CGRect) -> NSView { child.setAccessibilityHidden(false); view.addSubview(child); parts.append((child,rect)); return child }
    @discardableResult private func label(_ text: String, _ rect: CGRect, size: CGFloat = 13, muted: Bool = false, align: NSTextAlignment = .left) -> NSTextField {
        let field = NativeLabel(labelWithString:text); field.font = .systemFont(ofSize:size*s); field.textColor = muted ? InterfacePalette.muted : InterfacePalette.ink; field.alignment = align
        add(field,rect); return field
    }
    @discardableResult private func button(_ title: String, _ rect: CGRect, symbol: String? = nil, primary: Bool = false, muted: Bool = false, run: @escaping () -> Void) -> NativeButton {
        let b = NativeButton(title,symbol:symbol,action:run); b.font = .systemFont(ofSize:12*s); b.layoutScale = s; b.cornerSize = (primary ? 8 : 6)*s; b.primary = primary; b.muted = muted; add(b,rect); return b
    }
    private func separator(_ y: CGFloat) { let line = NSView(); line.wantsLayer = true; line.layer?.backgroundColor = resolvedColor(InterfacePalette.line); add(line,CGRect(x:0,y:y,width:480,height:1)) }
    private func render() {
        view.fill = state["glass"] as? Bool == true ? .clear : Style.canvas
        rows.fill = view.fill
        let responder = view.window?.firstResponder
        let searchFocused = responder === search || (search.currentEditor() != nil && responder === search.currentEditor())
        let searchSelection = (search.currentEditor() as? NSTextView)?.selectedRange()
        let offset = scroll.contentView.bounds.origin
        parts.removeAll(); view.subviews.forEach { $0.removeFromSuperview() }; meta = nil; saveState = nil; modeLabel = nil
        if page == "list" {
            let searchIcon = CompactIconView(); add(searchIcon,CGRect(x:17,y:19.72,width:17,height:17))
            search.font = .systemFont(ofSize:17*s); search.textColor = InterfacePalette.ink
            search.placeholderAttributedString = NSAttributedString(string:tr("搜索短语"),attributes:[.font:NSFont.systemFont(ofSize:17*s),.foregroundColor:InterfacePalette.muted])
            let expandText = (navLabel("down").isEmpty ? "↵" : navLabel("down"))+" "+tr("展开")
            let hintWidth = textWidth(expandText,size:12)
            add(search,CGRect(x:43,y:13.72,width:expanded ? 422 : 411-hintWidth,height:29))
            if !expanded { label(expandText,CGRect(x:463-hintWidth,y:13.72,width:hintWidth,height:29),size:12,muted:true,align:.right) }
            else {
                separator(56); scroll.documentView = rows; add(scroll,CGRect(x:7,y:64,width:466,height:314))
                separator(379)
                button(tr("新建短语"),CGRect(x:12,y:387.27,width:29,height:29),symbol:"plus",muted:true) { [weak self] in self?.edit(nil) }
                countLabel = label("\(matches.count)"+(AppText.language() == "en" && matches.count == 1 ? " item" : tr(" 条")),CGRect(x:47,y:387,width:80,height:29),size:10,muted:true)
                label(tr("⌘N 新建  ·  ⌘E 编辑  ·  ↵ 插入"),CGRect(x:108,y:387.27,width:264,height:29),size:10,muted:true,align:.center)
                button(tr("设置"),CGRect(x:439,y:387.27,width:29,height:29),symbol:"slider.horizontal.3",muted:true) { [weak self] in self?.show("settings") }
            }
            renderRows()
        } else {
            button(tr("返回"),CGRect(x:17,y:13.72,width:29,height:29),symbol:"arrow.left",muted:true) { [weak self] in self?.navigate { self?.show("list") } }
            label(tr(page == "settings" ? "设置" : page == "preview" ? "短语" : editing == nil ? "新建短语" : "编辑短语"),CGRect(x:57,y:14.22,width:220,height:28),size:14).font = .systemFont(ofSize:14*s,weight:.medium)
            separator(56)
            if page == "settings" { renderSettings() }
            else {
                editor.isSelectable = true; editor.isEditable = page == "editor"; editor.vimEnabled = page == "editor" && state["vimEditing"] as? Bool == true
                editor.font = .systemFont(ofSize:17*s); editor.textColor = InterfacePalette.ink; editor.insertionPointColor = .labelColor
                let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = 25.5*s; paragraph.maximumLineHeight = 25.5*s
                editor.defaultParagraphStyle = paragraph
                let baseline = max(0,(25.5*s-(editor.layoutManager?.defaultLineHeight(for:editor.font!) ?? 25.5*s))/2)
                editor.textStorage?.addAttributes([.font:NSFont.systemFont(ofSize:17*s),.foregroundColor:InterfacePalette.ink,.paragraphStyle:paragraph,.baselineOffset:baseline],range:NSRange(location:0,length:(editor.string as NSString).length))
                editor.typingAttributes = [.font:NSFont.systemFont(ofSize:17*s),.foregroundColor:InterfacePalette.ink,.paragraphStyle:paragraph,.baselineOffset:baseline]
                scroll.documentView = editor; add(scroll,CGRect(x:18,y:72,width:444,height:275.1))
                if page == "editor" {
                    let pinWidth = textWidth(tr("置顶"),size:11)+30
                    let pin = button(tr("置顶"),CGRect(x:463-pinWidth,y:15.44,width:pinWidth,height:25.56)) { [weak self] in guard let self else { return }; self.pinned.toggle(); self.updateDraft(); self.render() }
                    pin.font = .systemFont(ofSize:11*s); pin.leadingSymbol = "pin"; pin.symbolGap = 5; pin.selected = pinned
                    meta = label("",CGRect(x:18,y:355.1,width:110,height:13.89),size:10,muted:true)
                    modeLabel = label("",CGRect(x:26+textWidth("\(editor.string.count)"+tr(" 字符"),size:10),y:355.1,width:224,height:13.89),size:10,muted:true)
                    saveState = label("",CGRect(x:357,y:355.1,width:105,height:13.89),size:10,muted:true,align:.right); updateMeta()
                    separator(379)
                    button(tr("删除短语"),CGRect(x:12,y:387.27,width:29,height:29),symbol:"trash",muted:true) { [weak self] in self?.dialog = "delete"; self?.render(); self?.view.window?.makeFirstResponder(self?.view) }.isEnabled = editing != nil
                    label("⌘S "+tr("保存")+"  ·  Esc "+tr("取消"),CGRect(x:125,y:387,width:230,height:29),size:10,muted:true,align:.center)
                    button(tr("保存"),CGRect(x:414,y:386.44,width:54,height:30.66),primary:true) { [weak self] in self?.save() }
                } else {
                    let backText = (navLabel("back").isEmpty ? "Esc" : navLabel("back"))+" "+tr("返回")
                    let badgeWidth = textWidth(backText,size:10)+10
                    let badge = Surface(); badge.fill = InterfacePalette.hover; badge.radius = 4*s
                    add(badge,CGRect(x:463-badgeWidth,y:18.28,width:badgeWidth,height:19.88))
                    label(backText,CGRect(x:468-badgeWidth,y:18.28,width:badgeWidth-10,height:19.88),size:10,muted:true,align:.center)
                    separator(379); label(tr("纯文本"),CGRect(x:12,y:387.27,width:110,height:29),size:10,muted:true)
                    button(tr("编辑"),CGRect(x:346,y:387.44,width:42,height:28.66),muted:true) { [weak self] in if let p = self?.chosen { self?.edit(p) } }
                    button(tr("插入"),CGRect(x:394,y:386.44,width:74,height:30.66),primary:true) { [weak self] in self?.insert() }.trailingSymbol = "return"
                }
            }
        }
        if page == "settings", settingMenu != nil { renderSettingMenu() }
        if dialog != nil { renderDialog() }
        layout(); scroll.contentView.scroll(to:offset)
        if dialog == nil {
            if searchFocused && page == "list" {
                view.window?.makeFirstResponder(search)
                if let selection = searchSelection { (search.currentEditor() as? NSTextView)?.setSelectedRange(selection) }
            } else if let responder { view.window?.makeFirstResponder(responder) }
        }
        view.needsDisplay = true
    }
    private func layout() {
        // The same logical geometry is scaled in all three window sizes.
        let missing = max(0,424-view.bounds.height/s)
        for (child,source) in parts {
            var r = source
            if expanded || page != "list" {
                if r.minY >= 355 { r.origin.y -= missing }
                if child === scroll { r.size.height = max(40,r.height-missing) }
            }
            child.frame = CGRect(x:r.minX*s,y:r.minY*s,width:r.width*s,height:r.height*s)
        }
        if page == "list" { rows.frame.size.width = scroll.contentSize.width; for child in rows.subviews { child.frame.size.width = rows.bounds.width } }
        else if page != "settings" { editor.setFrameSize(NSSize(width:scroll.contentSize.width,height:max(scroll.contentSize.height,editor.frame.height))); editor.textContainer?.containerSize = NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude) }
    }
    private func renderRows() {
        if page != "list" { return }
        if expanded && scroll.superview == nil { render(); return }
        selected = max(0,min(selected,matches.count-1)); rows.subviews.forEach { $0.removeFromSuperview() }
        rows.frame = CGRect(x:0,y:0,width:466*s,height:max(314*s,CGFloat(matches.count)*46*s))
        for (i,p) in matches.enumerated() {
            let row = NativeRow(body:p["body"] as? String ?? "",selected:i == selected,scale:s) { [weak self] in self?.selected = i; self?.edit(p) }
            row.glass = state["glass"] as? Bool == true
            row.frame = CGRect(x:0,y:CGFloat(i)*46*s,width:466*s,height:46*s)
            row.choose = { [weak self] in self?.selected = i; self?.renderRows(); self?.focus() }
            row.insert = { [weak self] in self?.emit("insert",["id":p["id"] ?? ""]) }
            rows.addSubview(row)
        }
        countLabel?.stringValue = "\(matches.count)"+(AppText.language() == "en" && matches.count == 1 ? " item" : tr(" 条"))
        if matches.isEmpty {
            let field = NativeLabel(labelWithString:tr(prompts.isEmpty ? "还没有短语" : "没有匹配的短语")); field.font = .systemFont(ofSize:14*s); field.textColor = .secondaryLabelColor; field.alignment = .center; field.frame = CGRect(x:0,y:76*s,width:466*s,height:24*s); rows.addSubview(field)
        }
        if expanded { rows.scrollToVisible(CGRect(x:0,y:CGFloat(selected)*46*s,width:1,height:46*s)) }
    }
    private func renderSettings() {
        // 57-point header, eight 39-point rows, and the original 45-point footer.
        for child in view.subviews {
            if let field = child as? NativeLabel { field.font = .systemFont(ofSize:14*s,weight:.medium); field.textColor = InterfacePalette.ink }
            if let back = child as? NativeButton { back.inkColor = InterfacePalette.muted }
        }
        let titles = ["语言","快捷键方案","Vim 编辑模式","浮窗大小","外观","登录时启动","辅助功能权限","配置文件"]
        label("Popaste",CGRect(x:370,y:14,width:93,height:28),size:11,muted:true,align:.right).textColor = InterfacePalette.muted
        for (i,title) in titles.enumerated() {
            let y = CGFloat(57+i*39)
            label(tr(title),CGRect(x:18,y:y+5,width:170,height:28)).textColor = InterfacePalette.ink
            if i < 7 {
                let line = NSView(); line.wantsLayer = true; line.layer?.backgroundColor = resolvedColor(InterfacePalette.line)
                add(line,CGRect(x:18,y:y+38,width:444,height:1))
            }
        }
        select("language", options:[("system","跟随系统"),("zh-Hans","简体中文"),("zh-Hant","繁體中文"),("en","English"),("ja","日本語"),("ko","한국어"),("fr","Français"),("de","Deutsch"),("es","Español")], y:57)
        let keyOptions = [("arrows","↑ ↓ ← →"),("emacs","Emacs"),("vim","Vim")]
        let keyTitle = keyOptions.filter { schemes.contains($0.0) }.map { $0.1 }.joined(separator:" / ")
        let keyWidth = min(180,controlWidth(keyTitle.isEmpty ? "—" : keyTitle))
        let shortcutTitle = recording ? tr("按下组合键…") : state["shortcut"] as? String ?? ""
        let shortcutWidth = max(56,textWidth(shortcutTitle,size:12)+22)
        let recorder = button(shortcutTitle,CGRect(x:462-keyWidth-12-shortcutWidth,y:102,width:shortcutWidth,height:27)) { [weak self] in
            self?.recording = true; self?.emit("recording",["enabled":true]); self?.render(); self?.view.window?.makeFirstResponder(self?.view)
        }
        recorder.font = .systemFont(ofSize:12*s); recorder.outline = InterfacePalette.line; recorder.cornerSize = 7*s; recorder.inkColor = InterfacePalette.ink
        select("navigationSchemes",options:keyOptions,y:96,multiple:true)
        toggle("vimEditing",y:135,value:state["vimEditing"] as? Bool ?? false)
        let segmentTitles = ["小","中","大"].map(tr)
        let widths = segmentTitles.map { textWidth($0,size:11)+22 }
        let total = widths.reduce(0,+)+10
        let tray = NSView(); tray.wantsLayer = true; tray.layer?.backgroundColor = resolvedColor(InterfacePalette.hover); tray.layer?.cornerRadius = 7*s
        add(tray,CGRect(x:462-total,y:178.43,width:total,height:29.54))
        var x = 465-total
        for (i,value) in ["small","medium","large"].enumerated() {
            let b = button(segmentTitles[i],CGRect(x:x,y:181.42,width:widths[i],height:23.54)) { [weak self] in self?.emit("size",["value":value]) }
            b.font = .systemFont(ofSize:11*s); b.selected = state["size"] as? String == value
            b.selectedFill = InterfacePalette.paper; b.cornerSize = 5*s; b.inkColor = b.selected ? InterfacePalette.ink : InterfacePalette.muted
            x += widths[i]+2
        }
        select("appearance",options:[("system","跟随系统"),("light","浅色"),("dark","深色")],y:213)
        toggle("login",y:252,value:state["login"] as? Bool ?? false)
        let permitted = state["trusted"] as? Bool == true
        let permissionTitle = tr(permitted ? "已授权 ›" : "去授权 ›")
        let permissionWidth = textWidth(permissionTitle,size:11)+24
        let permission = button(permissionTitle,CGRect(x:462-permissionWidth,y:296,width:permissionWidth,height:28)) { [weak self] in self?.emit("permission") }
        permission.font = .systemFont(ofSize:11*s); permission.statusDot = true
        permission.inkColor = permitted ? NSColor(srgbRed:112/255,green:149/255,blue:128/255,alpha:1) : InterfacePalette.muted
        let pathX = 18+textWidth(tr("配置文件"),size:13)+12
        label("~/.config/popeste",CGRect(x:pathX,y:335,width:210,height:28),size:11,muted:true).textColor = InterfacePalette.muted
        let openWidth = textWidth(tr("打开"),size:12)+18
        let open = button(tr("打开"),CGRect(x:462-openWidth,y:335,width:openWidth,height:28),muted:true) { [weak self] in self?.emit("openDirectory") }
        open.font = .systemFont(ofSize:12*s); open.inkColor = InterfacePalette.muted
        separator(379)
        label(tr("更改后自动保存"),CGRect(x:12,y:387,width:330,height:29),size:10,muted:true).textColor = InterfacePalette.muted
        let doneWidth = textWidth(tr("完成"),size:12)+18
        let done = button(tr("完成"),CGRect(x:468-doneWidth,y:387,width:doneWidth,height:29),muted:true) { [weak self] in self?.show("list") }
        done.font = .systemFont(ofSize:12*s); done.inkColor = InterfacePalette.muted
    }
    private func resolvedColor(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }
    private func textWidth(_ text: String,size: CGFloat) -> CGFloat { (text as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:size)]).width }
    private func controlWidth(_ title: String) -> CGFloat { textWidth(title,size:12)+37 }
    private func toggle(_ name: String,y: CGFloat,value: Bool) {
        let toggle = SettingsToggle(tr(name == "login" ? "登录时启动" : "Vim 编辑模式"),enabled:value) { [weak self] enabled in self?.emit(name,["enabled":enabled]) }
        add(toggle,CGRect(x:432,y:y+10,width:30,height:18))
    }
    private func select(_ name: String,options:[(String,String)],y:CGFloat,multiple:Bool = false) {
        let values = multiple ? schemes : [state[name] as? String ?? "system"]
        let title = options.filter { values.contains($0.0) }.map { tr($0.1) }.joined(separator:" / ")
        let width = multiple ? min(180,controlWidth(title.isEmpty ? "—" : title)) : controlWidth(title)
        let b = button(title.isEmpty ? "—" : title,CGRect(x:462-width,y:y+5,width:width,height:28)) {}
        b.font = .systemFont(ofSize:12*s); b.inkColor = InterfacePalette.ink
        b.alignRight = true; b.trailingSymbol = "chevron.down"; b.symbolGap = 9
        b.invoke = { [weak self] in
            guard let self else { return }
            self.menuSelection = -1
            self.settingMenu = self.settingMenu?.name == name ? nil : SettingMenu(name:name,options:options,y:y,multiple:multiple)
            self.render(); self.view.window?.makeFirstResponder(self.view)
        }
    }
    private func chooseMenuItem(_ index: Int) {
        guard let menu = settingMenu, menu.options.indices.contains(index) else { return }
        let value = menu.options[index].0
        if !menu.multiple { settingMenu = nil }
        let next: Any = menu.multiple ? (schemes.contains(value) ? schemes.filter { $0 != value } : schemes+[value]) as Any : value as Any
        emit(menu.name,["value":next])
    }
    private func renderSettingMenu() {
        guard let menu = settingMenu else { return }
        let shield = SettingsMenuShield(); shield.dismiss = { [weak self] in self?.settingMenu = nil; self?.render() }
        add(shield,CGRect(x:0,y:0,width:480,height:424))
        let width = max(138,(menu.options.map { textWidth(tr($0.1),size:12)+46 }.max() ?? 138))
        let height = min(230,CGFloat(menu.options.count)*30+8)
        let box = Surface(); box.fill = InterfacePalette.paper; box.border = InterfacePalette.line; box.radius = 9*s
        box.frame = CGRect(x:(462-width)*s,y:(menu.y+36)*s,width:width*s,height:height*s)
        box.wantsLayer = true; box.layer?.shadowOpacity = 0.12; box.layer?.shadowRadius = 10*s; box.layer?.shadowOffset = CGSize(width:0,height:-3*s)
        shield.addSubview(box)
        let menuScroll = NSScrollView(frame:box.bounds.insetBy(dx:4*s,dy:4*s)); menuScroll.drawsBackground = false; menuScroll.hasVerticalScroller = true; menuScroll.autohidesScrollers = true
        let list = Surface(frame:CGRect(x:0,y:0,width:(width-8)*s,height:CGFloat(menu.options.count)*30*s)); list.fill = InterfacePalette.paper
        let values = menu.multiple ? schemes : [state[menu.name] as? String ?? "system"]
        for (i,option) in menu.options.enumerated() {
            let b = NativeButton(tr(option.1)) { [weak self] in self?.chooseMenuItem(i) }
            b.font = .systemFont(ofSize:12*s); b.layoutScale = s; b.inkColor = InterfacePalette.ink; b.alignLeft = true; b.checkState = values.contains(option.0)
            b.selected = i == menuSelection; b.selectedFill = InterfacePalette.hover; b.cornerSize = 5*s
            b.hoverAction = { [weak self, weak list] in
                self?.menuSelection = i
                for (index,child) in (list?.subviews ?? []).enumerated() {
                    (child as? NativeButton)?.selected = index == i; child.needsDisplay = true
                }
            }
            b.setAccessibilityValue(values.contains(option.0) ? 1 : 0)
            b.frame = CGRect(x:0,y:CGFloat(i)*30*s,width:(width-8)*s,height:30*s); list.addSubview(b)
        }
        menuScroll.documentView = list; box.addSubview(menuScroll)
        list.scrollToVisible(CGRect(x:0,y:CGFloat(max(0,menuSelection))*30*s,width:1,height:30*s))
    }
    private func renderDialog() {
        for child in view.subviews {
            child.setAccessibilityHidden(true)
            if let button = child as? NSButton { button.isEnabled = false }
        }
        editor.isEditable = false; editor.isSelectable = false
        let shade = NSView(); shade.wantsLayer = true; shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(2.0/15.0).cgColor; add(shade,CGRect(x:0,y:0,width:480,height:424))
        let box = Surface(); box.fill = InterfacePalette.paper; box.border = InterfacePalette.line; box.radius = 14*s
        add(box,CGRect(x:30,y:137.92,width:420,height:148.15))
        label(tr(dialog == "unsaved" ? "保存未完成的修改？" : "删除这条短语？"),CGRect(x:53,y:160.5,width:374,height:20),size:14).font = .systemFont(ofSize:14*s,weight:.semibold)
        label(tr(dialog == "unsaved" ? "当前修改尚未保存。" : "删除后无法恢复。"),CGRect(x:53,y:192.47,width:374,height:20.39),size:12,muted:true)
        let saveTitle = dialog == "unsaved" ? "↵ "+tr("保存") : tr("删除")
        let saveWidth = textWidth(saveTitle,size:12)+30
        let discardTitle = "N "+tr("放弃修改"), stayTitle = "Esc "+tr("返回")
        let discardWidth = textWidth(discardTitle,size:12)+10, stayWidth = textWidth(stayTitle,size:12)+10
        let saveX = 427.45-saveWidth, discardX = saveX-10-discardWidth
        let stayX = dialog == "unsaved" ? discardX-4-stayWidth : saveX-10-stayWidth
        button(stayTitle,CGRect(x:stayX,y:232.86,width:stayWidth,height:30.66),muted:true) { [weak self] in self?.closeDialog() }
        if dialog == "unsaved" { button(discardTitle,CGRect(x:discardX,y:232.86,width:discardWidth,height:30.66),muted:true) { [weak self] in let next = self?.leaveAction; self?.closeDialog(); next?() } }
        button(saveTitle,CGRect(x:saveX,y:232.86,width:saveWidth,height:30.66),primary:true) { [weak self] in self?.acceptDialog() }

    }
    func toast(_ text: String) {
        toastGeneration += 1; let generation = toastGeneration
        let field = label(text,CGRect(x:35,y:expanded || page != "list" ? 345 : 32,width:410,height:23),size:12,muted:true,align:.center); layout()
        DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self,weak field] in if self?.toastGeneration == generation { field?.removeFromSuperview() } }
    }
}
func interfacePrompts(_ prompts: [Prompt]) -> [[String: Any]] { prompts.map { ["id":$0.id.uuidString,"body":$0.body,"pinned":$0.pinned] } }
func interfaceDark(_ appearance: String = "system") -> Bool { appearance == "dark" || (appearance == "system" && NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua) }
