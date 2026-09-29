import AppKit

@main struct VimTests {
    static func main() {
        _ = NSApplication.shared
        let e = NativeEditor(frame:NSRect(x:0,y:0,width:130,height:300))
        let window = NSWindow(contentRect:e.frame,styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = e
        e.font = .systemFont(ofSize:17)
        e.textContainer?.containerSize = NSSize(width:130,height:10000)
        e.vimPasteboard = .withUniqueName()
        defer { e.vimPasteboard.releaseGlobally() }
        e.allowsUndo = true; e.vimEnabled = true
        func load(_ text: String) {
            e.resetCommand(); e.normal = true; e.string = text; e.cursor(0); e.undoManager?.removeAllActions()
        }
        func key(_ text: String, flags: NSEvent.ModifierFlags = [], code: UInt16 = 0) {
            let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!
            _ = e.handleVim(event)
        }
        func keys(_ value: String) { for char in value { key(String(char)) } }
        load("one two three"); keys("w"); assert(e.selectedRange().location == 4)
        keys("e"); assert(e.selectedRange().location == 6)
        keys("b"); assert(e.selectedRange().location == 4)
        keys("0dw"); assert(e.string == "two three")
        keys("u"); assert(e.string == "one two three")
        key("r",flags:.control); assert(e.string == "two three")
        load("one two three four five six seven"); keys("2d3w"); assert(e.string == "seven")
        load("one two"); keys("cw"); assert(e.string == " two" && !e.normal)
        key("\u{1b}",code:53); assert(e.normal)
        load("abc def"); keys("vll"); assert(e.isVisual && e.selectedRange() == NSRange(location:0,length:3))
        keys("y"); assert(!e.isVisual && e.vimPasteboard.string(forType:.string) == "abc")
        keys("$p"); assert(e.string == "abc defabc")
        load("abc def"); keys("llvh"); assert(e.selectedRange() == NSRange(location:1,length:2))
        key("\u{1b}",code:53); assert(!e.isVisual && e.selectedRange().location == 1)
        load("one\ntwo\nthree"); keys("Vjy"); assert(e.vimPasteboard.string(forType:.string) == "one\ntwo\n")
        keys("Gp"); assert(e.string == "one\ntwo\nthree\none\ntwo")
        load("one\ntwo\n"); keys("jdd"); assert(e.string == "one\n")
        load("one\ntwo"); keys("jdd"); assert(e.string == "one")
        load("one\ntwo"); keys("cc"); assert(e.string == "\ntwo" && !e.normal)
        load("A👨‍👩‍👧‍👦你好"); keys("lvy"); assert(e.vimPasteboard.string(forType:.string) == "👨‍👩‍👧‍👦")
        keys("p"); assert(e.string == "A👨‍👩‍👧‍👦👨‍👩‍👧‍👦你好" && e.selectedRange().location == 12)
        load("abc"); keys("vl"); key("c",flags:.command); assert(e.vimPasteboard.string(forType:.string) == "ab")
        key("x",flags:.command); assert(e.string == "c")
        key("v",flags:.command); assert(e.string == "cab")
        load("abc"); keys("2rZ"); assert(e.string == "ZZc")
        load("one\ntwo\nthree"); keys("3gg"); assert(e.selectedRange().location == 8)
        keys("gg"); assert(e.selectedRange().location == 0)
        keys("d$"); assert(e.string == "\ntwo\nthree")
        load(String(repeating:"abcdefghij ",count:20)); keys("vj"); assert(e.selectedRange().length > 2)
        keys("k"); assert(e.selectedRange() == NSRange(location:0,length:1))
        key("\u{1b}",code:53); assert(!e.isVisual && !e.consumesEscape)
        keys("d"); assert(e.consumesEscape); key("\u{1b}",code:53); assert(!e.consumesEscape)
        print("Native Vim tests passed")
    }
}
