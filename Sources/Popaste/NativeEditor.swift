import AppKit

/// TextKit supplies glyph geometry for both the block cursor and wrapped-line motion.
final class NativeEditor: NSTextView {
    var route: ((NSEvent) -> Bool)?
    var modeChanged: (() -> Void)?
    var vimEnabled = false { didSet { if oldValue != vimEnabled { normal = vimEnabled; resetCommand() } } }
    var normal = false { didSet { needsDisplay = true; updateInsertionPointStateAndRestartTimer(true); modeChanged?() } }
    private var pending = "", count = "", register = ""
    private var preferredX: CGFloat?
    private var anchor: Int?
    private var head = 0
    private var linewise = false
    private var registerIsLine = false
    private var operatorCount = 1
    var vimPasteboard = NSPasteboard.general
    var isVisual: Bool { anchor != nil }
    var consumesEscape: Bool { !normal || isVisual || !pending.isEmpty || !count.isEmpty }
    private var position: Int { isVisual ? head : selectedRange().location }
    private func leaveVisual() { anchor = nil; linewise = false; modeChanged?() }
    private func remember(_ range: NSRange, lines: Bool) {
        register = text.substring(with: range)
        if lines && !register.hasSuffix("\n") { register += "\n" }
        registerIsLine = lines
        vimPasteboard.clearContents()
        vimPasteboard.setString(register, forType: .string)
    }
    override func copy(_ sender: Any?) {
        guard normal else { super.copy(sender); return }
        if selectedRange().length > 0 { remember(selectedRange(), lines: linewise) }
    }
    override var shouldDrawInsertionPoint: Bool { !normal && super.shouldDrawInsertionPoint }
    func resetCommand() { pending = ""; count = ""; preferredX = nil; operatorCount = 1; leaveVisual() }
    override func keyDown(with event: NSEvent) {
        if hasMarkedText() { super.keyDown(with: event); return }
        if route?(event) == true { return }
        if vimEnabled && handleVim(event) { return }
        if normal { return }
        super.keyDown(with: event)
    }
    override func paste(_ sender: Any?) { if normal { put(before: false, count: 1) } else { super.paste(sender) } }
    override func cut(_ sender: Any?) { if normal && selectedRange().length > 0 { operate("d", range: selectedRange(), lines: linewise) } else if !normal { super.cut(sender) } }
    override func insertText(_ insertString: Any, replacementRange: NSRange) { if !normal { super.insertText(insertString, replacementRange: replacementRange) } }
    override func mouseDown(with event: NSEvent) { leaveVisual(); preferredX = nil; super.mouseDown(with: event); if normal { cursor(selectedRange().location) }; needsDisplay = true }
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
        var p = min(max(0, position), text.length)
        if p < text.length { p = text.rangeOfComposedCharacterSequence(at:p).location }; let l = line(p)
        if p == NSMaxRange(l) && p > l.location { p = previous(p) }
        if let start = anchor {
            head = p
            var low = min(start,p), high = next(max(start,p))
            if linewise { low = line(low).location; high = fullLineEnd(max(start,p)) }
            setSelectedRange(NSRange(location: low, length: high-low))
        } else { setSelectedRange(NSRange(location: p, length: 0)) }
        scrollRangeToVisible(NSRange(location:p,length:0)); needsDisplay = true
    }
    private func replace(_ range: NSRange, with value: String, at position: Int, insert: Bool = false) {
        if !insert { breakUndoCoalescing() }
        guard shouldChangeText(in: range, replacementString: value) else { return }
        textStorage?.replaceCharacters(in: range, with: value); didChangeText()
        if insert { setSelectedRange(NSRange(location: position, length: 0)) } else { cursor(position) }
    }
    private func fullLineEnd(_ p: Int) -> Int {
        let end = NSMaxRange(line(p))
        return end < text.length ? next(end) : end
    }
    private func category(_ p: Int, big: Bool) -> Int {
        guard p < text.length else { return 0 }
        let value = text.substring(with:text.rangeOfComposedCharacterSequence(at:p))
        if value.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { return 0 }
        return big || value.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) || $0 == "_" }) ? 1 : 2
    }
    private func word(_ start: Int, key: String, count: Int) -> Int {
        var p = start
        let big = key == key.uppercased()
        for _ in 0..<count {
            if key.lowercased() == "b" {
                p = previous(p)
                while p > 0 && category(p,big:big) == 0 { p = previous(p) }
                let kind = category(p,big:big)
                while p > 0 && category(previous(p),big:big) == kind { p = previous(p) }
            } else if key.lowercased() == "e" {
                p = next(p)
                while p < text.length && category(p,big:big) == 0 { p = next(p) }
                let kind = category(p,big:big)
                while next(p) < text.length && category(next(p),big:big) == kind { p = next(p) }
            } else {
                let kind = category(p,big:big)
                while p < text.length && category(p,big:big) == kind { p = next(p) }
                while p < text.length && category(p,big:big) == 0 { p = next(p) }
            }
        }
        return p
    }
    private func operate(_ op: String, range: NSRange, lines: Bool = false) {
        if range.length == 0 {
            leaveVisual()
            if op == "c" { normal = false }
            return
        }
        remember(range, lines:lines)
        leaveVisual()
        if op == "y" { cursor(range.location); return }
        var deletion = range
        if lines && op == "d" && NSMaxRange(range) == text.length && range.location > 0 && !string.hasSuffix("\n") {
            deletion.location = previous(range.location); deletion.length = NSMaxRange(range)-deletion.location
        }
        normal = op != "c"
        let replacement = lines && op == "c" && NSMaxRange(range) < text.length ? "\n" : ""
        replace(deletion,with:replacement,at:min(deletion.location,text.length-deletion.length),insert:op == "c")
    }
    private func put(before: Bool, count: Int) {
        guard let value = vimPasteboard.string(forType:.string), !value.isEmpty else { return }
        let lines = value == register ? registerIsLine : value.hasSuffix("\n")
        let block = String(repeating:value,count:count)
        if isVisual {
            let range = selectedRange(); leaveVisual()
            replace(range,with:block,at:range.location); return
        }
        let p = position, l = line(p), end = NSMaxRange(l)
        if lines {
            if before { replace(NSRange(location:l.location,length:0),with:block,at:l.location) }
            else if end < text.length { replace(NSRange(location:end+1,length:0),with:block,at:end+1) }
            else { replace(NSRange(location:end,length:0),with:"\n"+String(block.dropLast()),at:end+1) }
        } else {
            let at = before ? p : min(end,next(p))
            replace(NSRange(location:at,length:0),with:block,at:at+(block as NSString).length-1)
        }
    }
    func handleVim(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers ?? "", flags = event.modifierFlags
        if !normal {
            if event.keyCode == 53 { normal = true; resetCommand(); breakUndoCoalescing(); cursor(max(line(position).location,previous(position))); return true }
            return false
        }
        if flags.contains(.control) && key.lowercased() == "r" { leaveVisual(); undoManager?.redo(); cursor(selectedRange().location); return true }
        if flags.contains(.command) {
            switch key.lowercased() {
            case "c": copy(nil); return true
            case "v": paste(nil); return true
            case "x": cut(nil); return true
            default: return false
            }
        }
        if !flags.intersection([.control,.option]).isEmpty { return false }
        if event.keyCode == 53 {
            let consume = consumesEscape, p = position
            resetCommand(); cursor(p); return consume
        }
        if key.count == 1, let digit = key.first, digit.isASCII && digit.isNumber, (digit != "0" || !count.isEmpty), pending != "r" {
            count = String((count+key).prefix(3)); return true
        }
        let explicitCount = !count.isEmpty
        let n = max(1,min(999,(Int(count) ?? 1)*operatorCount)); count = ""; operatorCount = 1
        let pos = position, l = line(pos), end = NSMaxRange(l)
        let op = pending; pending = ""
        if op == "r" {
            if key.count == 1 {
                var last = pos, chars = 0
                for _ in 0..<n where last < end { last = next(last); chars += 1 }
                replace(NSRange(location:pos,length:last-pos),with:String(repeating:key,count:chars),at:pos)
            }; return true
        }
        if op == "g" {
            if key == "g" { var p = 0; for _ in 1..<n { p = fullLineEnd(p) }; cursor(p) }
            return true
        }
        if !op.isEmpty && op == key {
            var last = pos
            for _ in 0..<n { last = fullLineEnd(last) }
            operate(op,range:NSRange(location:l.location,length:last-l.location),lines:true); return true
        }
        if !["j","k","\u{f700}","\u{f701}"].contains(key) { preferredX = nil }
        var target: Int?, inclusive = false, lines = false
        switch key {
        case "h", "\u{f702}": var p = pos; for _ in 0..<n { p = max(l.location,previous(p)) }; target = p
        case "l", "\u{f703}": var p = pos; for _ in 0..<n { p = min(end,next(p)) }; target = p
        case "j", "k", "\u{f700}", "\u{f701}":
            moveVisual(["j","\u{f701}"].contains(key) ? n : -n)
            if op.isEmpty { return true }; target = position; lines = true
        case "w","W","b","B","e","E":
            let motion = op == "c" && key.lowercased() == "w" && category(pos,big:false) != 0 ? (key == "w" ? "e" : "E") : key
            target = word(pos,key:motion,count:n); inclusive = motion.lowercased() == "e"
        case "0": target = l.location
        case "^": var p = l.location; while p < end && category(p,big:false) == 0 { p = next(p) }; target = p
        case "$": target = end
        case "G":
            var p = explicitCount ? 0 : text.length
            if explicitCount { for _ in 1..<n { p = fullLineEnd(p) } }; target = p; lines = true
        default: break
        }
        if let destination = target {
            if op.isEmpty { cursor(destination) }
            else {
                let low = lines ? line(min(pos,destination)).location : min(pos,destination)
                let high = lines ? fullLineEnd(max(pos,destination)) : (inclusive ? next(max(pos,destination)) : max(pos,destination))
                operate(op,range:NSRange(location:low,length:high-low),lines:lines)
            }; return true
        }
        if !op.isEmpty { return true }
        switch key {
        case "v","V":
            if isVisual && linewise == (key == "V") { leaveVisual(); cursor(pos) }
            else { anchor = anchor ?? pos; head = pos; linewise = key == "V"; cursor(pos); modeChanged?() }
        case "d","y","c":
            if isVisual { operate(key,range:selectedRange(),lines:linewise) }
            else { pending = key; operatorCount = n }
        case "g","r": pending = key; operatorCount = n
        case "i","a","I","A":
            leaveVisual(); normal = false; breakUndoCoalescing()
            var p = pos
            if key == "a" { p = min(end,next(pos)) }; if key == "A" { p = end }
            if key == "I" { p = l.location; while p < end && category(p,big:false) == 0 { p = next(p) } }
            setSelectedRange(NSRange(location:p,length:0))
        case "o","O":
            leaveVisual(); normal = false; breakUndoCoalescing(); let at = key == "o" ? end : l.location
            replace(NSRange(location:at,length:0),with:"\n",at:at+(key == "o" ? 1 : 0),insert:true)
        case "x","s","D","C","Y":
            if isVisual { operate(key == "s" || key == "C" ? "c" : key == "Y" ? "y" : "d",range:selectedRange(),lines:linewise) }
            else if key == "Y" { operate("y",range:NSRange(location:l.location,length:fullLineEnd(pos)-l.location),lines:true) }
            else {
                var last = pos; for _ in 0..<n { last = min(end,next(last)) }
                if key == "D" || key == "C" { last = end }
                operate(key == "s" || key == "C" ? "c" : "d",range:NSRange(location:pos,length:last-pos))
            }
        case "p","P": put(before:key == "P",count:n)
        case "u": leaveVisual(); for _ in 0..<n { undoManager?.undo() }; cursor(selectedRange().location)
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
        guard let current = points.min(by: { abs($0.position-position) < abs($1.position-position) }) else { return }
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
        let p = min(position,text.length), origin = textContainerOrigin
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
