import AppKit
import QuartzCore

/// The panel's entire interface is native AppKit. It shares the existing persistence actions.
final class NativeInterface: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
    let view = NativeCanvas()
    var action: ((String, [String: Any]) -> Void)?
    var state: [String: Any] = [:] { didSet { applyState() } }
    private let search = NativeSearch()
    private let editor = NativeEditor()
    private let scroll = NSScrollView()
    private let rows = NativeCanvas()
    private let listTagsScroll = TagScrollView()
    private let editorTagsScroll = TagScrollView()
    private var selectedTags: [String] = []
    private var activeTab = "all"
    private var renamingTag = ""
    private var renamingActiveTag = false
    private var editingTag: String?
    private var tagEditorDrafts: [String:(name:String,color:String,visible:Bool)] = [:]
    private var tagVisible = true
    private var tagColor = "#3B82F6"
    private weak var tagColorButton: NativeButton?
    private var tagPresetButtons: [(hex:String,button:NativeButton)] = []
    private var ownsTagColorPicker = false
    private let tagNameField = NSTextField()
    private var draftTags: [String] { Prompt.normalizedTags(selectedTags) }
    private var allTagNames: [String] {
        TagOrder.sorted(prompts.flatMap { $0["tags"] as? [String] ?? [] },preferred:state["tagOrder"] as? [String] ?? [])
    }
    private var tabs: [(String, String)] {
        let hidden = Set((state["hiddenTags"] as? [String] ?? []).map { $0.lowercased() })
        let names = allTagNames.filter { !hidden.contains($0.lowercased()) }
        return [("all",tr("全部")),("recent",tr("最近使用"))] + names.map { ("tag:"+$0.lowercased(), $0) }
    }
    private var parts: [(NSView, CGRect)] = []
    private var trailingParts = Set<ObjectIdentifier>()
    private var dialogParts = Set<ObjectIdentifier>()
    private var page = "list", query = ""
    private var expanded = true, selected = 0, recording = false
    private var searchVisible = false
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
        let filtered = prompts.filter { p in
            let tags = p["tags"] as? [String] ?? []
            let scope = activeTab == "all" || (activeTab == "recent" ? p["lastUsed"] as? Double != nil : tags.contains { "tag:"+$0.lowercased() == activeTab })
            return scope && terms.allSatisfy { (p["body"] as? String ?? "").localizedCaseInsensitiveContains($0) }
        }
        return activeTab == "recent" ? filtered.sorted { ($0["lastUsed"] as? Double ?? 0) > ($1["lastUsed"] as? Double ?? 0) } : filtered
    }
    private var chosen: [String: Any]? { matches.indices.contains(selected) ? matches[selected] : nil }
    private var dirty: Bool { page == "editor" && (draftTags != (editing?["tags"] as? [String] ?? []) || editor.string != (editing?["body"] as? String ?? "") || pinned != (editing?["pinned"] as? Bool ?? false)) }
    init(mode: String) {
        super.init()
        view.autoresizingMask = [.width,.height]
        view.layoutContent = { [weak self] in self?.layout() }
        view.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        tagNameField.delegate = self; tagNameField.isBordered = false; tagNameField.drawsBackground = false; tagNameField.focusRingType = .none
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
        scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
    }
    private func emit(_ name: String, _ payload: [String: Any] = [:]) { action?(name,payload) }
    private func applyState() {
        if !tabs.contains(where: { $0.0 == activeTab }) { activeTab = "all" }
        let oldID = chosen?["id"] as? String
        // Glass supplies its adaptive appearance to content; only solid views set their own.
        view.appearance = state["glass"] as? Bool == true ? nil : NSAppearance(named:(state["dark"] as? Bool == true) ? .darkAqua : .aqua)
        if let oldID, let i = matches.firstIndex(where: { $0["id"] as? String == oldID }) { selected = i }
        editor.vimEnabled = page == "editor" && state["vimEditing"] as? Bool == true
        render()
    }
    private func sync() { emit("layout",["page":page,"collapsed":page == "list" && !expanded,"minimumHeight":CGFloat(page != "list" ? 424 : editingTag != nil ? 360 : searchVisible ? 196 : 140)]) }
    func focus() { view.window?.makeFirstResponder(page == "list" ? (searchVisible ? search : view) : page == "editor" ? editor : view) }
    func open(_ destination: String = "resume") {
        if dialog != nil && destination != "resume" { return }
        if (search.currentEditor() as? NSTextView)?.hasMarkedText() == true || editor.hasMarkedText() { return }
        if recording && ["new","edit","settings"].contains(destination) { return }
        recording = false; emit("recording",["enabled":false])
        switch destination {
        case "new": edit(nil)
        case "edit": if page == "list" || page == "preview", let chosen { edit(chosen) }
        case "settings": navigate { self.show("settings") }
        case "list": navigate { self.query = ""; self.search.stringValue = ""; self.searchVisible = false; self.show("list") }
        default:
            if page == "list" { query = ""; search.stringValue = ""; selected = 0; expanded = true; searchVisible = false; sync(); render() }
        }
        DispatchQueue.main.async { [weak self] in self?.focus() }
    }
    func call(_ name: String, _ argument: Any) {
        if name == "nativeTagRenamed", let value = argument as? String {
            closeTagColorPicker(); editingTag = nil; tagEditorDrafts.removeAll()
            if renamingActiveTag { activeTab = value.isEmpty ? "all" : "tag:"+value.lowercased() }
            selectedTags = Prompt.normalizedTags(selectedTags.map { $0.lowercased() == renamingTag.lowercased() ? value : $0 })
            if let tags = editing?["tags"] as? [String] { editing?["tags"] = Prompt.normalizedTags(tags.map { $0.lowercased() == renamingTag.lowercased() ? value : $0 }) }
            if page == "editor" { updateDraft() }
            render(); focus(); return
        }
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
        settingMenu = nil; closeTagColorPicker(); editingTag = nil; tagEditorDrafts.removeAll()
        page = next; if next == "list" { expanded = true }
        recording = false; emit("recording",["enabled":false]); sync(); render(); focus()
    }
    private func navigate(_ next: @escaping () -> Void) {
        if dirty { leaveAction = next; dialog = "unsaved"; render(); view.window?.makeFirstResponder(view) } else { next() }
    }
    private func edit(_ phrase: [String: Any]?) {
        let offset = page == "preview" ? scroll.contentView.bounds.origin : .zero
        navigate {
            self.show("editor"); self.editing = phrase; self.pinned = phrase?["pinned"] as? Bool ?? false
            self.selectedTags = (phrase?["tags"] as? [String] ?? (self.tabs.first(where: { $0.0 == self.activeTab && $0.0.hasPrefix("tag:") }).map { [$0.1] } ?? []))
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
    private func updateDraft() { emit("draft",["id":editing?["id"] as? String ?? "","body":editor.string,"pinned":pinned,"tags":draftTags]); updateMeta() }
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
        saving = true; emit("save",["id":editing?["id"] as? String ?? "","body":editor.string,"pinned":pinned,"tags":draftTags])
    }
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === tagNameField { tagNameField.textColor = InterfacePalette.ink; return }
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
        if editingTag != nil {
            if (tagNameField.currentEditor() as? NSTextView)?.hasMarkedText() == true { return false }
            if event.keyCode == 53 { closeTagEditor(); return true }
            if event.keyCode == 36 { saveTagEditor(); return true }
            return false
        }
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
            if key == "f", page == "list" { revealSearch(); return true }
            if key == "v", page == "list", !searchVisible { revealSearch(); (search.currentEditor() as? NSTextView)?.paste(nil); return true }
            if key == "n" { edit(nil); return true }
            if key == "," { navigate { self.show("settings") }; return true }
            if key == "e", page == "list" || page == "preview" { if let chosen { edit(chosen) }; return true }
            if key == "s", page == "editor" { save(); return true }
        }
        if page == "editor", editor.vimEnabled && !editor.normal && event.keyCode == 53 { return false }
        if event.keyCode == 53 {
            if page == "list", searchVisible {
                view.window?.makeFirstResponder(view)
                search.stringValue = ""; query = ""; searchVisible = false; selected = 0
                render(); focus()
            } else if page == "list" { emit("dismiss",["explicit":true]) }
            else { navigate { self.show("list") } }
            return true
        }
        if (flags == .control || flags == .command) && event.keyCode == 36 && (page == "list" || page == "preview") { insert(continuous:true); return true }
        if page == "preview" {
            if nav(event,"back") { show("list"); return true }
            if event.keyCode == 36 { insert(); return true }
        }
        if page == "list" {
            if !expanded && (event.keyCode == 36 || nav(event,"down") || nav(event,"up")) { expanded = true; selected = 0; sync(); render(); focus(); return true }
            if nav(event,"down") || nav(event,"up") { selected += nav(event,"down") ? 1 : -1; renderRows(); return true }
            if nav(event,"forward") || nav(event,"back") {
                let index = tabs.firstIndex(where: { $0.0 == activeTab }) ?? 0
                selectTab(tabs[max(0,min(tabs.count-1,index+(nav(event,"forward") ? 1 : -1)))].0)
                return true
            }
            if event.keyCode == 36 { insert(); return true }
            if flags == [.command,.shift] && key == "c", let body = chosen?["body"] { emit("copy",["body":body]); return true }
        }
        if page == "list", !searchVisible,
           flags.intersection([.command,.control]).isEmpty,
           let characters = event.characters, !characters.isEmpty,
           characters.unicodeScalars.contains(where: { !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) {
            revealSearch()
            // Deliver the original key to AppKit's field editor so IME composition and
            // keyboard layouts work exactly as they do in a visible text field.
            search.currentEditor()?.keyDown(with:event)
            return true
        }
        return false
    }
    private func revealSearch() {
        guard !searchVisible else { return }
        searchVisible = true; render(); focus()
        guard view.window?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        for (child,rect) in parts where rect.minY < 355 && rect.height < 424 {
            child.wantsLayer = true
            guard let layer = child.layer else { continue }
            let slide = CABasicAnimation(keyPath:"position.y")
            slide.fromValue = layer.position.y - (rect.minY < 56 ? 8 : 56)*s
            slide.toValue = layer.position.y
            slide.duration = 0.1; slide.timingFunction = CAMediaTimingFunction(name:.easeOut)
            layer.add(slide,forKey:"search-reveal-position")
            if rect.minY < 56 {
                let fade = CABasicAnimation(keyPath:"opacity")
                fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.1
                layer.add(fade,forKey:"search-reveal-opacity")
            }
        }
    }
    private func insert(continuous: Bool = false) { if let id = chosen?["id"] { emit("insert",["id":id,"continuous":continuous]) } }
    private func closeDialog() { guard !saving else { return }; dialog = nil; leaveAction = nil; afterSave = nil; render(); focus() }
    private func acceptDialog() {
        if dialog == "unsaved" { afterSave = leaveAction; save() }
        else if let id = editing?["id"] { dialog = nil; emit("delete",["id":id]) }
    }
    @discardableResult private func add(_ child: NSView, _ rect: CGRect) -> NSView { child.setAccessibilityHidden(false); view.addSubview(child); parts.append((child,rect)); return child }
    @discardableResult private func label(_ text: String, _ rect: CGRect, size: CGFloat = 13, muted: Bool = false, align: NSTextAlignment = .left) -> NSTextField {
        let field = NativeLabel(labelWithString:text); field.font = .systemFont(ofSize:size*s); field.textColor = muted ? InterfacePalette.muted : InterfacePalette.ink; field.alignment = align
        if text.contains("↵") {
            let value = KeyHintText.attributed(text,font:field.font!,color:field.textColor!)
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = align; paragraph.lineBreakMode = .byClipping
            value.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:value.length))
            field.maximumNumberOfLines = 1; field.attributedStringValue = value
        }
        add(field,rect); return field
    }
    @discardableResult private func button(_ title: String, _ rect: CGRect, symbol: String? = nil, primary: Bool = false, muted: Bool = false, run: @escaping () -> Void) -> NativeButton {
        let b = NativeButton(title,symbol:symbol,action:run); b.font = .systemFont(ofSize:12*s); b.layoutScale = s; b.cornerSize = (primary ? 8 : 6)*s; b.primary = primary; b.muted = muted; add(b,rect); return b
    }
    private func separator(_ y: CGFloat) { let line = NSView(); line.wantsLayer = true; line.layer?.backgroundColor = resolvedColor(InterfacePalette.line); add(line,CGRect(x:0,y:y,width:480,height:1)) }
    private func render() {
        sync()
        let glass = state["glass"] as? Bool == true
        // Regular supplies contrast through its adaptive material. Clear keeps its backing.
        let clearGlass = state["glassStyle"] as? String != "regular"
        let backingOpacity: CGFloat = clearGlass ? 0.55 : 0
        view.fill = glass ? Style.canvas.withAlphaComponent(backingOpacity) : Style.canvas
        rows.fill = glass ? .clear : Style.canvas
        let responder = view.window?.firstResponder
        let searchFocused = responder === search || (search.currentEditor() != nil && responder === search.currentEditor())
        let searchSelection = (search.currentEditor() as? NSTextView)?.selectedRange()
        let offset = scroll.contentView.bounds.origin
        parts.removeAll(); trailingParts.removeAll(); dialogParts.removeAll(); view.subviews.forEach { $0.removeFromSuperview() }; meta = nil; saveState = nil; modeLabel = nil
        if page == "list" {
            if searchVisible {
                let searchBox = Surface()
                searchBox.identifier = NSUserInterfaceItemIdentifier("inline-search")
                searchBox.radius = 20*s
                searchBox.fill = NSColor.controlBackgroundColor.withAlphaComponent(glass ? 0.35 : 0.8)
                add(searchBox,CGRect(x:12,y:10,width:456,height:40))
            }
            let searchIcon = CompactIconView(); searchIcon.isHidden = !searchVisible; search.isHidden = !searchVisible
            add(searchIcon,CGRect(x:24,y:22,width:16,height:16))
            search.font = .systemFont(ofSize:17*s); search.textColor = InterfacePalette.ink
            search.placeholderAttributedString = NSAttributedString(string:tr("搜索短语"),attributes:[.font:NSFont.systemFont(ofSize:17*s),.foregroundColor:InterfacePalette.muted])
            let searchHeight = (search.cell?.cellSize.height ?? 20*s)/s
            add(search,CGRect(x:48,y:30-searchHeight/2,width:408,height:searchHeight))
            renderTabs(); scroll.documentView = rows; add(scroll,CGRect(x:7,y:104,width:466,height:274))
            separator(379)
            button(tr("新建短语"),CGRect(x:12,y:387.27,width:29,height:29),symbol:"plus",muted:true) { [weak self] in self?.edit(nil) }
            countLabel = label("\(matches.count)"+(AppText.language() == "en" && matches.count == 1 ? " item" : tr(" 条")),CGRect(x:47,y:387,width:80,height:29),size:10,muted:true)
            label(tr("⌘N 新建  ·  ⌘E 编辑  ·  ↵ 插入  ·  ⌘↵ 连续插入"),CGRect(x:108,y:387.27,width:264,height:29),size:10,muted:true,align:.center)
            button(tr("设置"),CGRect(x:439,y:387.27,width:29,height:29),symbol:"slider.horizontal.3",muted:true) { [weak self] in self?.show("settings") }
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
                scroll.documentView = editor; add(scroll,CGRect(x:18,y:page == "editor" ? 112 : 72,width:444,height:page == "editor" ? 235.1 : 275.1))
                if page == "editor" {
                    renderEditorTags()
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
        // Reserve the trailing footer control for the window pin on every page.
        if expanded || page != "list" {
            for index in parts.indices where parts[index].1.minY >= 379 && parts[index].1.minX >= 394 {
                parts[index].1.origin.x -= 36
                trailingParts.insert(ObjectIdentifier(parts[index].0))
            }
        }
        let windowPinned = state["windowPinned"] as? Bool == true
        let pinTitle = tr(windowPinned ? "取消固定窗口" : "固定窗口")
        let windowPin = button(pinTitle,CGRect(x:439,y:page == "list" && !expanded ? 13.72 : 387.27,width:29,height:29),symbol:windowPinned ? "pin" : "pin.slash",muted:!windowPinned) { [weak self] in self?.emit("toggleWindowPin") }
        windowPin.selected = windowPinned
        windowPin.toolTip = pinTitle
        windowPin.setAccessibilityValue(windowPinned ? 1 : 0)
        if settingMenu != nil { renderSettingMenu() }
        if editingTag != nil { renderTagEditor() }
        if dialog != nil {
            let start = parts.count
            renderDialog()
            for (child,rect) in parts[start...] where rect.height < 424 { dialogParts.insert(ObjectIdentifier(child)) }
        }
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
        let dw = view.bounds.width/s-480
        let dh = view.bounds.height/s-424
        for (child,source) in parts {
            var r = source
            let id = ObjectIdentifier(child)
            if source.width == 480 && source.height == 424 {
                r.size = CGSize(width:view.bounds.width/s,height:view.bounds.height/s)
            } else if dialogParts.contains(id) {
                r.origin.x += dw/2; r.origin.y += dh/2
            } else {
                if child === search || source.width >= 400 {
                    r.size.width = max(1,r.width+dw)
                } else if child is GlassSurface || (child as? NSTextField)?.alignment == .center {
                    r.origin.x += dw/2
                } else if trailingParts.contains(id) || source.minX >= 300 || source.maxX >= 450 {
                    r.origin.x += dw
                }
                if expanded || page != "list" {
                    if r.minY >= (page == "settings" ? 379 : 355) { r.origin.y += dh }
                    if child === scroll { r.size.height = max(40,r.height+dh) }
                }
            }
            if page == "list", !searchVisible, source.minY >= 56, source.minY < 355,
               source.height != 424, !dialogParts.contains(id) {
                r.origin.y -= 56
                if child === scroll { r.size.height += 56 }
            }
            let frame = CGRect(x:r.minX*s,y:r.minY*s,width:r.width*s,height:r.height*s)
            child.frame = child === search ? view.backingAlignedRect(frame,options:.alignAllEdgesNearest) : frame
        }
        if page == "list" { rows.frame.size.width = scroll.contentSize.width; for child in rows.subviews { child.frame.size.width = rows.bounds.width } }
        else if page != "settings" { editor.setFrameSize(NSSize(width:scroll.contentSize.width,height:max(scroll.contentSize.height,editor.frame.height))); editor.textContainer?.containerSize = NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude) }
    }
    private func selectTab(_ id: String) {
        activeTab = id; selected = 0; expanded = true
        sync(); render(); scroll.contentView.scroll(to: .zero); focus()
    }
    private func tagPill(_ name: String, selected: Bool, choose: @escaping () -> Void) -> NativeTagPill {
        let pill = NativeTagPill(name:name,selected:selected,scale:s,customColor:(state["tagColors"] as? [String:String])?[name.lowercased()],choose: { [weak self] in
            if self?.editingTag != nil { self?.openTagEditor(name) } else { choose() }
        })
        pill.editButton.invoke = { [weak self] in self?.openTagEditor(name) }
        return pill
    }
    private func closeTagEditor() {
        closeTagColorPicker(); editingTag = nil; tagEditorDrafts.removeAll(); render(); focus()
    }
    private func openTagEditor(_ name: String) {
        closeTagColorPicker()
        if let current = editingTag {
            tagEditorDrafts[current.lowercased()] = (tagNameField.stringValue,tagColor,tagVisible)
        }
        editingTag = name
        let draft = tagEditorDrafts[name.lowercased()]
        tagVisible = draft?.visible ?? !(state["hiddenTags"] as? [String] ?? []).contains { $0.lowercased() == name.lowercased() }
        tagNameField.stringValue = draft?.name ?? name
        tagColor = draft?.color ?? (state["tagColors"] as? [String:String])?[name.lowercased()] ?? InterfacePalette.initialTagColor(name)
        render(); view.window?.makeFirstResponder(tagNameField)
    }
    private func saveTagEditor() {
        guard let old = editingTag else { return }
        let name = tagNameField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else { tagNameField.textColor = .systemRed; return }
        let raw = tagColor.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let color = TagColor.normalized(raw) else { return }
        renamingTag = old; renamingActiveTag = activeTab == "tag:"+old.lowercased()
        if old.isEmpty || !prompts.contains(where:{ ($0["tags"] as? [String] ?? []).contains { $0.lowercased() == old.lowercased() } }) {
            selectedTags = Prompt.normalizedTags(selectedTags.filter { $0.lowercased() != old.lowercased() } + [name])
            closeTagColorPicker(); editingTag = nil; tagEditorDrafts.removeAll(); updateDraft(); emit("tagColor",["old":old,"name":name,"value":color,"visible":tagVisible]); render(); focus()
        } else { emit("updateTag",["old":old,"name":name,"color":color,"visible":tagVisible]) }
    }
    private func deleteEditedTag() {
        guard let name = editingTag, !name.isEmpty else { return }
        renamingTag = name; renamingActiveTag = activeTab == "tag:"+name.lowercased()
        if prompts.contains(where:{ ($0["tags"] as? [String] ?? []).contains { $0.lowercased() == name.lowercased() } }) { emit("deleteTag",["name":name]) }
        else { selectedTags.removeAll { $0.lowercased() == name.lowercased() }; closeTagColorPicker(); editingTag = nil; tagEditorDrafts.removeAll(); updateDraft(); render(); focus() }
    }
    var tagColorPickerWindow: NSWindow? {
        let panel = NSColorPanel.shared
        return ownsTagColorPicker && panel.isVisible ? panel : nil
    }
    func closeTagColorPicker() {
        let panel = NSColorPanel.shared
        guard ownsTagColorPicker else { return }
        ownsTagColorPicker = false
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil); panel.setTarget(nil); panel.setAction(nil)
    }
    private func selectedTagColor() -> NSColor {
        let rgb = UInt32(tagColor.dropFirst(),radix:16) ?? 0x3B82F6
        return NSColor(srgbRed:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:1)
    }
    private func openTagColorPicker() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false; panel.isContinuous = true
        panel.color = selectedTagColor(); panel.setTarget(self); panel.setAction(#selector(changeTagColor(_:)))
        ownsTagColorPicker = true
        panel.level = NSWindow.Level(rawValue:NSWindow.Level.popUpMenu.rawValue+1)
        if let window = view.window { window.addChildWindow(panel,ordered:.above) }
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func changeTagColor(_ sender: NSColorPanel) {
        guard editingTag != nil, let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        tagColor = String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
        updateTagColorControls()
    }
    private func updateTagColorControls() {
        let customSelected = !tagPresetButtons.contains { $0.hex == tagColor }
        tagColorButton?.outline = customSelected ? InterfacePalette.ink : nil
        tagColorButton?.setAccessibilityValue(customSelected ? 1 : 0)
        tagColorButton?.normalFill = selectedTagColor(); tagColorButton?.selectedFill = selectedTagColor(); tagColorButton?.needsDisplay = true
        for (hex,button) in tagPresetButtons {
            let selected = tagColor == hex
            button.outline = selected ? InterfacePalette.ink : nil
            button.setAccessibilityValue(selected ? 1 : 0); button.needsDisplay = true
        }
    }
    private func renderTagEditor() {
        guard let name = editingTag else { return }
        editor.isEditable = false; editor.isSelectable = false
        view.window?.invalidateCursorRects(for:editor)
        let cancel: () -> Void = { [weak self] in self?.closeTagEditor() }
        let shield = TagEditorShield(); shield.dismiss = cancel
        shield.tagBar = page == "editor" ? editorTagsScroll : listTagsScroll
        add(shield,CGRect(x:0,y:0,width:480,height:424))
        let panelRect = CGRect(x:60,y:108,width:360,height:236)
        let surface = GlassSurface(frame:CGRect(x:0,y:0,width:360*s,height:236*s))
        let content = NativeCanvas(frame:surface.bounds); content.usesArrowCursor = true
        surface.install(content)
        surface.update(scale:s,dark:state["dark"] as? Bool ?? false,style:state["glassStyle"] as? String ?? "clear")
        surface.layer?.borderWidth = 1
        surface.layer?.borderColor = resolvedColor(InterfacePalette.muted.withAlphaComponent(0.3))
        content.fill = surface.glassEnabled ? view.fill : Style.canvas
        add(surface,panelRect)
        let firstPart = parts.count
        label(tr(name.isEmpty ? "新建标签" : "编辑标签"),CGRect(x:20,y:14,width:320,height:26),size:14)
        let nameBacking = Surface(); nameBacking.fill = InterfacePalette.hover; nameBacking.radius = 7*s
        add(nameBacking,CGRect(x:20,y:52,width:320,height:34))
        tagNameField.font = .systemFont(ofSize:14*s); tagNameField.textColor = InterfacePalette.ink
        tagNameField.placeholderString = tr("标签名称"); tagNameField.setAccessibilityLabel(tr("标签名称"))
        let nameHeight = (tagNameField.cell?.cellSize.height ?? 20*s)/s
        add(tagNameField,CGRect(x:30,y:69-nameHeight/2,width:300,height:nameHeight))
        let colorButton = button("",CGRect(x:20,y:103,width:26,height:26)) { [weak self] in self?.openTagColorPicker() }
        colorButton.normalFill = selectedTagColor(); colorButton.selectedFill = selectedTagColor(); colorButton.cornerSize = 13*s
        colorButton.setAccessibilityLabel(tr("标签颜色")); tagColorButton = colorButton
        let divider = NSView(); divider.wantsLayer = true; divider.layer?.backgroundColor = resolvedColor(InterfacePalette.muted.withAlphaComponent(0.3))
        add(divider,CGRect(x:60,y:104,width:1,height:24))
        tagPresetButtons.removeAll()
        let presets = ["#3B82F6","#14B8A6","#8B5CF6","#F59E0B","#EC4899","#65A30D","#EF4444","#64748B"]
        for (index,hex) in presets.enumerated() {
            let swatch = button("",CGRect(x:76+CGFloat(index)*34,y:103,width:26,height:26)) { [weak self] in
                self?.closeTagColorPicker(); self?.tagColor = hex; self?.updateTagColorControls()
            }
            let rgb = UInt32(hex.dropFirst(),radix:16)!
            swatch.normalFill = NSColor(srgbRed:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:1)
            swatch.selectedFill = swatch.normalFill; swatch.cornerSize = 13*s
            swatch.setAccessibilityLabel(hex); swatch.setAccessibilityRole(.radioButton)
            tagPresetButtons.append((hex,swatch))
        }
        updateTagColorControls()
        label(tr("在顶部显示"),CGRect(x:20,y:145,width:260,height:30),size:12)
        let visibility = SettingsToggle(tr("在顶部显示"),enabled:tagVisible) { [weak self] visible in self?.tagVisible = visible }
        add(visibility,CGRect(x:310,y:151,width:30,height:18))
        let line = NSView(); line.wantsLayer = true; line.layer?.backgroundColor = resolvedColor(InterfacePalette.line)
        add(line,CGRect(x:0,y:186,width:360,height:1))
        if !name.isEmpty {
            button(tr("删除标签"),CGRect(x:15,y:195,width:29,height:29),symbol:"trash",muted:true) { [weak self] in self?.deleteEditedTag() }
        }
        let cancelWidth = textWidth(tr("取消"),size:12)+20
        button(tr("取消"),CGRect(x:274-cancelWidth-12,y:195,width:cancelWidth,height:29),muted:true,run:cancel)
        button(tr("保存"),CGRect(x:286,y:195,width:54,height:30),primary:true) { [weak self] in self?.saveTagEditor() }
        // Keep popup content within the same glass surface and appearance as the main window.
        let popupParts = Array(parts[firstPart...]); parts.removeSubrange(firstPart...)
        for (child,rect) in popupParts {
            child.removeFromSuperview(); content.addSubview(child)
            child.frame = CGRect(x:rect.minX*s,y:rect.minY*s,width:rect.width*s,height:rect.height*s)
        }
    }
    private func renderEditorTags() {
        let strip = editorTagsScroll
        let offset = strip.contentView.bounds.origin
         strip.drawsBackground = false; strip.borderType = .noBorder
        let content = NativeTagStrip()
        content.reorder = { [weak self] order in
            guard let self else { return }; self.emit("tagOrder",["value":TagOrder.merging(order,into:self.allTagNames)])
        }
        var x: CGFloat = 0; var activeRect = CGRect.zero
        let noneWidth = (textWidth(tr("无标签"),size:12)+22)*s
        let none = NativeButton(tr("无标签")) { [weak self] in
            self?.selectedTags = []; self?.updateDraft(); self?.render(); self?.focus()
        }
        none.font = .systemFont(ofSize:12*s); none.selected = draftTags.isEmpty; none.cornerSize = 14*s; none.muted = !none.selected
        none.frame = CGRect(x:0,y:0,width:noneWidth,height:28*s); content.addSubview(none); x = noneWidth+6*s
        let names = Prompt.normalizedTags(allTagNames + draftTags)
        for name in names {
            let selected = draftTags.contains { $0.lowercased() == name.lowercased() }
            let pill = tagPill(name,selected:selected) { [weak self] in
                guard let self else { return }
                if self.draftTags.contains(where:{ $0.lowercased() == name.lowercased() }) { self.selectedTags.removeAll { $0.lowercased() == name.lowercased() } }
                else { self.selectedTags.append(name) }
                self.updateDraft(); self.render(); self.focus()
            }
            pill.frame = CGRect(x:x,y:0,width:min(180,(name as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12)]).width+22)*s,height:28*s)
            if selected { activeRect = pill.frame }
            content.addSubview(pill); x += pill.frame.width+6*s
        }
        let addTag = NativeButton(tr("新建标签"),symbol:"plus") { [weak self] in self?.openTagEditor("") }
        addTag.font = .systemFont(ofSize:12*s); addTag.layoutScale = s; addTag.iconSize = 14; addTag.muted = true
        addTag.frame = CGRect(x:x,y:0,width:28*s,height:28*s); content.addSubview(addTag); x += 28*s
        content.frame = CGRect(x:0,y:0,width:x,height:28*s); strip.documentView = content
        add(strip,CGRect(x:18,y:71,width:444,height:30)); strip.frame = CGRect(x:18*s,y:71*s,width:444*s,height:30*s)
        strip.contentView.scroll(to:offset)
        content.scrollToVisible(activeRect)
    }
    private func renderTabs() {
        let strip = listTagsScroll
        let offset = strip.contentView.bounds.origin
         strip.drawsBackground = false; strip.borderType = .noBorder
        strip.hasHorizontalScroller = false; strip.hasVerticalScroller = false
        let content = NativeTagStrip()
        content.reorder = { [weak self] order in
            guard let self else { return }; self.emit("tagOrder",["value":TagOrder.merging(order,into:self.allTagNames)])
        }
        var x: CGFloat = 0
        var activeRect = CGRect.zero
        for (id,title) in tabs {
            let custom = id.hasPrefix("tag:")
            let titleWidth = (title as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12)]).width
            let width = min(180,custom ? titleWidth+22 : max(44,titleWidth+22))*s
            let tab: NSView
            if custom { tab = tagPill(title,selected:id == activeTab) { [weak self] in self?.selectTab(id) } }
            else {
                let button = NativeButton(title) { [weak self] in self?.selectTab(id) }
                button.font = .systemFont(ofSize:12*s); button.selected = id == activeTab
                button.cornerSize = 14*s; button.muted = !button.selected
                button.setAccessibilityRole(.radioButton); button.setAccessibilityValue(button.selected ? 1 : 0)
                tab = button
            }
            tab.frame = CGRect(x:x,y:0,width:width,height:28*s)
            if id == activeTab { activeRect = tab.frame }
            content.addSubview(tab); x += width+4*s
        }
        content.frame = CGRect(x:0,y:0,width:x,height:28*s)
        strip.documentView = content
        add(strip,CGRect(x:12,y:65,width:456,height:30))
        strip.frame = CGRect(x:12*s,y:65*s,width:456*s,height:30*s)
        strip.contentView.scroll(to:offset)
        content.scrollToVisible(activeRect)
    }
    private func renderRows() {
        if page != "list" { return }
        if expanded && scroll.superview == nil { render(); return }
        selected = max(0,min(selected,matches.count-1)); rows.subviews.forEach { $0.removeFromSuperview() }
        rows.frame = CGRect(x:0,y:0,width:scroll.contentSize.width,height:max(scroll.contentSize.height,CGFloat(matches.count)*46*s))
        for (i,p) in matches.enumerated() {
            let row = NativeRow(body:p["body"] as? String ?? "",tags:p["tags"] as? [String] ?? [],tagColors:state["tagColors"] as? [String:String] ?? [:],selected:i == selected,scale:s) { [weak self] in self?.selected = i; self?.edit(p) }
            row.glass = state["glass"] as? Bool == true
            row.frame = CGRect(x:0,y:CGFloat(i)*46*s,width:scroll.contentSize.width,height:46*s)
            row.choose = { [weak self] in self?.selected = i; self?.renderRows(); self?.focus() }
            row.insert = { [weak self] in self?.emit("insert",["id":p["id"] ?? ""]) }
            rows.addSubview(row)
        }
        countLabel?.stringValue = "\(matches.count)"+(AppText.language() == "en" && matches.count == 1 ? " item" : tr(" 条"))
        if matches.isEmpty {
            let field = NativeLabel(labelWithString:tr(prompts.isEmpty ? "还没有短语" : "没有匹配的短语")); field.font = .systemFont(ofSize:14*s); field.textColor = .secondaryLabelColor; field.alignment = .center; field.frame = CGRect(x:0,y:76*s,width:scroll.contentSize.width,height:24*s); rows.addSubview(field)
        }
        if expanded { rows.scrollToVisible(CGRect(x:0,y:CGFloat(selected)*46*s,width:1,height:46*s)) }
    }
    private func renderSettings() {
        // Hide unavailable glass controls and keep the remaining settings contiguous.
        for child in view.subviews {
            if let field = child as? NativeLabel { field.font = .systemFont(ofSize:14*s,weight:.medium); field.textColor = InterfacePalette.ink }
            if let back = child as? NativeButton { back.inkColor = InterfacePalette.muted }
            if child is NativeLabel || child is NativeButton,
               let index = parts.firstIndex(where:{ $0.0 === child }) {
                parts[index].1.origin.y = 28-parts[index].1.height/2
            }
        }
        let glassAvailable = state["glass"] as? Bool == true
        let titles = ["语言","快捷键方案","Vim 编辑模式","浮窗大小","外观"]
            + (glassAvailable ? ["玻璃样式"] : [])
            + ["登录时启动","辅助功能权限","配置文件"]
        func rowY(_ title: String) -> CGFloat { CGFloat(57 + (titles.firstIndex(of:title) ?? 0) * 32) }
        let brandWidth = textWidth("Popeste",size:11)+4
        let logo = NSImageView()
        logo.image = NSImage(size:NSSize(width:26,height:26),flipped:false) { _ in
            BrandIcon.drawAppIcon(size:26); return true
        }
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.setAccessibilityLabel("Popeste")
        add(logo,CGRect(x:463-brandWidth-26,y:15,width:26,height:26))
        label("Popeste",CGRect(x:463-brandWidth,y:14,width:brandWidth,height:28),size:11,muted:true,align:.right).textColor = InterfacePalette.muted
        for (i,title) in titles.enumerated() {
            let y = CGFloat(57+i*32)
            let labelY = settingsControlY(row:y,height:28)
            label(tr(title),CGRect(x:18,y:labelY,width:170,height:28)).textColor = InterfacePalette.ink
            if i < titles.count - 1 {
                let line = NSView(); line.wantsLayer = true; line.layer?.backgroundColor = resolvedColor(InterfacePalette.line)
                add(line,CGRect(x:18,y:y+31,width:444,height:1))
            }
        }
        select("language", options:[("system","跟随系统"),("zh-Hans","简体中文"),("zh-Hant","繁體中文"),("en","English"),("ja","日本語"),("ko","한국어"),("fr","Français"),("de","Deutsch"),("es","Español")], y:rowY("语言"))
        let keyOptions = [("arrows","↑ ↓ ← →"),("emacs","Emacs"),("vim","Vim")]
        let keyTitle = keyOptions.filter { schemes.contains($0.0) }.map { $0.1 }.joined(separator:" / ")
        let keyWidth = min(180,controlWidth(keyTitle.isEmpty ? "—" : keyTitle))
        let shortcutTitle = recording ? tr("按下组合键…") : state["shortcut"] as? String ?? ""
        let shortcutWidth = max(56,textWidth(shortcutTitle,size:12)+22)
        let recorder = button(shortcutTitle,CGRect(x:462-keyWidth-12-shortcutWidth,y:settingsControlY(row:rowY("快捷键方案"),height:27),width:shortcutWidth,height:27)) { [weak self] in
            self?.recording = true; self?.emit("recording",["enabled":true]); self?.render(); self?.view.window?.makeFirstResponder(self?.view)
        }
        trailingParts.insert(ObjectIdentifier(recorder))
        recorder.font = .systemFont(ofSize:12*s); recorder.outline = InterfacePalette.line; recorder.cornerSize = 7*s; recorder.inkColor = InterfacePalette.ink
        select("navigationSchemes",options:keyOptions,y:rowY("快捷键方案"),multiple:true)
        toggle("vimEditing",y:rowY("Vim 编辑模式"),value:state["vimEditing"] as? Bool ?? false)
        let segmentTitles = ["小","中","大"].map(tr)
        let sizeValues = ["small","medium","large"]
        let selectedSize = sizeValues.firstIndex(of:state["size"] as? String ?? "large") ?? 2
        let width = max(114,segmentTitles.map { textWidth($0,size:11)+26 }.max()! * 3)
        let sizeControl: NSView
        if #available(macOS 26.0, *), glassAvailable {
            sizeControl = GlassSizeSelector(labels:segmentTitles,selected:selectedSize,scale:s) { [weak self] index in
                self?.emit("size",["value":sizeValues[index]])
            }
        } else {
            let control = NSSegmentedControl(labels:segmentTitles,trackingMode:.selectOne,target:self,action:#selector(changePickerSize(_:)))
            control.segmentStyle = .automatic; control.controlSize = .small
            control.font = .systemFont(ofSize:11*s); control.segmentDistribution = .fillEqually
            control.selectedSegment = selectedSize; control.setAccessibilityLabel(tr("浮窗大小"))
            sizeControl = control
        }
        add(sizeControl,CGRect(x:462-width,y:settingsControlY(row:rowY("浮窗大小"),height:30),width:width,height:30))
        select("appearance",options:[("system","跟随系统"),("light","浅色"),("dark","深色")],y:rowY("外观"))
        if glassAvailable {
            select("glassStyle",options:[("regular","磨砂玻璃"),("clear","液态玻璃")],y:rowY("玻璃样式"))
        }
        toggle("login",y:rowY("登录时启动"),value:state["login"] as? Bool ?? false)
        let permitted = state["trusted"] as? Bool == true
        let permissionTitle = tr(permitted ? "已授权 ›" : "去授权 ›")
        let permissionWidth = textWidth(permissionTitle,size:11)+24
        let permission = button(permissionTitle,CGRect(x:462-permissionWidth,y:settingsControlY(row:rowY("辅助功能权限"),height:28),width:permissionWidth,height:28)) { [weak self] in self?.emit("permission") }
        permission.font = .systemFont(ofSize:11*s); permission.statusDot = true
        permission.inkColor = permitted ? NSColor(srgbRed:112/255,green:149/255,blue:128/255,alpha:1) : InterfacePalette.muted
        let pathX = 18+textWidth(tr("配置文件"),size:13)+12
        label("~/.config/popeste",CGRect(x:pathX,y:settingsControlY(row:rowY("配置文件"),height:28),width:210,height:28),size:11,muted:true).textColor = InterfacePalette.muted
        let openWidth = textWidth(tr("打开"),size:12)+18
        let open = button(tr("打开"),CGRect(x:462-openWidth,y:settingsControlY(row:rowY("配置文件"),height:28),width:openWidth,height:28),muted:true) { [weak self] in self?.emit("openDirectory") }
        open.font = .systemFont(ofSize:12*s); open.inkColor = InterfacePalette.muted
        separator(379)
        label(tr("更改后自动保存"),CGRect(x:12,y:387,width:330,height:29),size:10,muted:true).textColor = InterfacePalette.muted
        let doneWidth = textWidth(tr("完成"),size:12)+18
        let done = button(tr("完成"),CGRect(x:468-doneWidth,y:387,width:doneWidth,height:29),muted:true) { [weak self] in self?.show("list") }
        done.font = .systemFont(ofSize:12*s); done.inkColor = InterfacePalette.muted
    }
    @objc private func changePickerSize(_ sender: NSSegmentedControl) {
        let sizes = ["small","medium","large"]
        guard sizes.indices.contains(sender.selectedSegment) else { return }
        emit("size",["value":sizes[sender.selectedSegment]])
    }
    private func resolvedColor(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }
    private func textWidth(_ text: String,size: CGFloat) -> CGFloat { (text as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:size)]).width }
    private func controlWidth(_ title: String) -> CGFloat { textWidth(title,size:12)+37 }
    private func settingsControlY(row:CGFloat,height:CGFloat) -> CGFloat { row+(32-height)/2 }
    private func toggle(_ name: String,y: CGFloat,value: Bool) {
        let toggle = SettingsToggle(tr(name == "login" ? "登录时启动" : name == "expandOnShow" ? "呼出时展开" : "Vim 编辑模式"),enabled:value) { [weak self] enabled in self?.emit(name,["enabled":enabled]) }
        add(toggle,CGRect(x:432,y:settingsControlY(row:y,height:18),width:30,height:18))
    }
    private func select(_ name: String,options:[(String,String)],y:CGFloat,multiple:Bool = false) {
        let values = multiple ? schemes : [state[name] as? String ?? "system"]
        let title = options.filter { values.contains($0.0) }.map { tr($0.1) }.joined(separator:" / ")
        let width = multiple ? min(180,controlWidth(title.isEmpty ? "—" : title)) : controlWidth(title)
        let b = button(title.isEmpty ? "—" : title,CGRect(x:462-width,y:settingsControlY(row:y,height:28),width:width,height:28)) {}
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
        let width = min(374,max(138,(menu.options.map { textWidth(tr($0.1),size:12)+46 }.max() ?? 138)))
        let height = min(230,CGFloat(menu.options.count)*30+8)
        shield.frame = view.bounds
        let box = Surface(); box.fill = InterfacePalette.paper; box.border = InterfacePalette.line; box.radius = 9*s
        box.autoresizingMask = [.minXMargin]
        box.frame = CGRect(x:view.bounds.width-(18+width)*s,y:(menu.y+36)*s,width:width*s,height:height*s)
        box.wantsLayer = true; box.layer?.shadowOpacity = 0.12; box.layer?.shadowRadius = 10*s; box.layer?.shadowOffset = CGSize(width:0,height:-3*s)
        shield.addSubview(box)
        let menuScroll = NSScrollView(frame:box.bounds.insetBy(dx:4*s,dy:4*s)); menuScroll.drawsBackground = false; menuScroll.hasVerticalScroller = false; menuScroll.hasHorizontalScroller = false
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
func interfacePrompts(_ prompts: [Prompt]) -> [[String: Any]] {
    prompts.map { p in
        var value: [String: Any] = ["id":p.id.uuidString,"body":p.body,"pinned":p.pinned,"tags":p.tags]
        if let date = p.lastUsed { value["lastUsed"] = date.timeIntervalSince1970 }
        return value
    }
}
func interfaceDark(_ appearance: String = "system") -> Bool { appearance == "dark" || (appearance == "system" && NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua) }
