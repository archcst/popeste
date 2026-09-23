import AppKit

/// TextKit supplies glyph geometry for both the block cursor and wrapped-line motion.
final class NativeEditor: NSTextView {
    var route: ((NSEvent) -> Bool)?
    var modeChanged: (() -> Void)?
    var vimEnabled = false { didSet { if oldValue != vimEnabled { normal = vimEnabled; resetCommand() } } }
    var normal = false { didSet { needsDisplay = true; updateInsertionPointStateAndRestartTimer(true); modeChanged?() } }
    private var pending = "", count = "", register = ""
    private var preferredX: CGFloat?
    override var shouldDrawInsertionPoint: Bool { !normal && super.shouldDrawInsertionPoint }
    func resetCommand() { pending = ""; count = ""; preferredX = nil }
    override func keyDown(with event: NSEvent) {
        if hasMarkedText() { super.keyDown(with: event); return }
        if route?(event) == true { return }
        if vimEnabled && handleVim(event) { return }
        if normal { return }
        super.keyDown(with: event)
    }
    override func paste(_ sender: Any?) { if !normal { super.paste(sender) } }
    override func cut(_ sender: Any?) { if !normal { super.cut(sender) } }
    override func insertText(_ insertString: Any, replacementRange: NSRange) { if !normal { super.insertText(insertString, replacementRange: replacementRange) } }
    override func mouseDown(with event: NSEvent) { preferredX = nil; super.mouseDown(with: event); if normal { cursor(selectedRange().location) }; needsDisplay = true }
    override func setSelectedRange(_ charRange: NSRange) { super.setSelectedRange(charRange); needsDisplay = true }
    private var text: NSString { string as NSString }
    private func line(_ position: Int) -> NSRange {
        let p = min(max(0, position), text.length)
        var start = 0, end = 0, content = 0
        text.getLineStart(&start, end: &end, contentsEnd: &content, for: NSRange(location: p, length: 0))
        return NSRange(location: start, length: content-start)
    }
    private func next(_ pos: Int) -> Int { pos < text.length ? NSMaxRange(text.rangeOfComposedCharacterSequence(at: pos)) : pos }
    private func previous(_ pos: Int) -> Int { pos > 0 ? text.rangeOfComposedCharacterSequence(at: pos-1).location : 0 }
    func cursor(_ position: Int) {
        var p = min(max(0, position), text.length); let l = line(p)
        if p == NSMaxRange(l) && p > l.location { p = previous(p) }
        setSelectedRange(NSRange(location: p, length: 0)); scrollRangeToVisible(selectedRange()); needsDisplay = true
    }
    private func replace(_ range: NSRange, with value: String, at position: Int, insert: Bool = false) {
        if !insert { breakUndoCoalescing() }
        guard shouldChangeText(in: range, replacementString: value) else { return }
        textStorage?.replaceCharacters(in: range, with: value); didChangeText()
        if insert { setSelectedRange(NSRange(location: position, length: 0)) } else { cursor(position) }
    }
    func handleVim(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers ?? "", flags = event.modifierFlags
        if !normal {
            if event.keyCode == 53 { normal = true; resetCommand(); breakUndoCoalescing(); cursor(max(line(selectedRange().location).location,previous(selectedRange().location))); return true }
            return false
        }
        if flags.contains(.control) && key.lowercased() == "r" { undoManager?.redo(); cursor(selectedRange().location); return true }
        if flags.intersection([.command, .control, .option]).isEmpty == false { return false }
        if event.keyCode == 53 { resetCommand(); return false }
        if key.count == 1, let digit = key.first, digit.isNumber, (digit != "0" || !count.isEmpty) { count = String((count+key).prefix(4)); return true }
        let n = min(999, Int(count) ?? 1); count = ""
        let pos = selectedRange().location, l = line(pos), end = NSMaxRange(l)
        if !pending.isEmpty {
            let op = pending; pending = ""
            if key == op {
                var last = end
                for _ in 1..<max(1,n) { if last < text.length { last = NSMaxRange(line(last+1)) } }
                register = text.substring(with: NSRange(location: l.location, length: last-l.location))+"\n"
                if op == "d" {
                    let after = last < text.length ? last+1 : last
                    let start = last == text.length && l.location > 0 ? l.location-1 : l.location
                    replace(NSRange(location: start, length: after-start), with: "", at: l.location)
                }
            }; return true
        }
        if !["j","k","\u{f700}","\u{f701}"].contains(key) { preferredX = nil }
        switch key {
        case "h", "\u{f702}": var p = pos; for _ in 0..<n { p = max(l.location, previous(p)) }; cursor(p)
        case "l", "\u{f703}": var p = pos; for _ in 0..<n { p = min(end, next(p)) }; cursor(p)
        case "j", "\u{f701}": moveVisual(n)
        case "k", "\u{f700}": moveVisual(-n)
        case "0": cursor(l.location)
        case "$": cursor(end)
        case "i", "a", "I", "A":
            normal = false; breakUndoCoalescing()
            var p = pos
            if key == "a" { p = min(end,next(pos)) }; if key == "A" { p = end }
            if key == "I" { p = l.location; while p < end, let scalar = UnicodeScalar(text.character(at: p)), CharacterSet.whitespaces.contains(scalar) { p += 1 } }
            setSelectedRange(NSRange(location: p,length: 0))
        case "o", "O":
            normal = false; breakUndoCoalescing(); let at = key == "o" ? end : l.location
            replace(NSRange(location: at,length: 0),with: "\n",at: at+(key == "o" ? 1 : 0),insert: true)
        case "d", "y": pending = key; count = n == 1 ? "" : String(n)
        case "x": var p = pos; for _ in 0..<n { p = min(end,next(p)) }; replace(NSRange(location: pos,length: p-pos),with: "",at: pos)
        case "p", "P":
            if !register.isEmpty {
                let block = String(repeating: register,count: n)
                if key == "P" { replace(NSRange(location: l.location,length: 0),with: block,at: l.location) }
                else if end < text.length { replace(NSRange(location: end+1,length: 0),with: block,at: end+1) }
                else { replace(NSRange(location: end,length: 0),with: "\n"+String(block.dropLast()),at: end+1) }
            }
        case "u": for _ in 0..<n { undoManager?.undo() }; cursor(selectedRange().location)
        default: break
        }
        return true
    }
    func moveVisual(_ delta: Int) {
        guard let lm = layoutManager, let container = textContainer else { return }
        lm.ensureLayout(for: container)
        struct Point { let position: Int; let x: CGFloat; let y: CGFloat }
        var points: [Point] = []; var p = 0
        while p < text.length {
            let l = line(p)
            if p < NSMaxRange(l) || l.length == 0 {
                let glyph = lm.glyphIndexForCharacter(at: p)
                let rect = lm.lineFragmentRect(forGlyphAt: glyph,effectiveRange: nil)
                points.append(Point(position: p,x: rect.minX+lm.location(forGlyphAt: glyph).x,y: rect.minY))
            }; p = next(p)
        }
        if text.length == 0 || string.hasSuffix("\n") { points.append(Point(position: text.length,x: lm.extraLineFragmentRect.minX,y: lm.extraLineFragmentRect.minY)) }
        guard let current = points.min(by: { abs($0.position-selectedRange().location) < abs($1.position-selectedRange().location) }) else { return }
        let rows = Array(Set(points.map(\.y))).sorted(); let row = rows.firstIndex(of: current.y) ?? 0
        let y = rows[min(max(0,row+delta),rows.count-1)], x = preferredX ?? current.x
        preferredX = x
        if let target = points.filter({ $0.y == y }).min(by: { abs($0.x-x) < abs($1.x-x) }) { cursor(target.position) }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && isEditable && !vimEnabled {
            NSAttributedString(string:tr("输入短语正文…"),attributes:[.font:font ?? NSFont.systemFont(ofSize:17),.foregroundColor:InterfacePalette.muted]).draw(at:textContainerOrigin)
        }
        guard normal, window?.firstResponder === self, let lm = layoutManager, let container = textContainer else { return }
        lm.ensureLayout(for: container)
        let p = min(selectedRange().location,text.length), origin = textContainerOrigin
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua
        var rect: NSRect; var glyphRange = NSRange(location: 0,length: 0)
        if p < text.length {
            let charRange = text.rangeOfComposedCharacterSequence(at: p)
            glyphRange = lm.glyphRange(forCharacterRange: charRange,actualCharacterRange: nil)
            rect = lm.boundingRect(forGlyphRange: glyphRange,in: container)
            if rect.width < 1 { rect.size.width = (font?.pointSize ?? 17)*0.6 }
        } else { rect = lm.extraLineFragmentRect; if rect.height == 0 { rect = NSRect(x: 0,y: 0,width: 0,height: (font?.pointSize ?? 17)*1.4) }; rect.size.width = (font?.pointSize ?? 17)*0.6 }
        rect.origin.x += origin.x; rect.origin.y += origin.y
        (dark ? NSColor.white : .black).setFill(); rect.fill()
        if glyphRange.length > 0 {
            NSGraphicsContext.saveGraphicsState(); rect.clip()
            let chars = lm.characterRange(forGlyphRange: glyphRange,actualGlyphRange: nil)
            lm.addTemporaryAttribute(.foregroundColor,value: dark ? NSColor.black : .white,forCharacterRange: chars)
            lm.drawGlyphs(forGlyphRange: glyphRange,at: origin)
            lm.removeTemporaryAttribute(.foregroundColor,forCharacterRange: chars)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
