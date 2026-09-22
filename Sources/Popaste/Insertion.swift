import AppKit
import ApplicationServices

final class Insertion {
    private(set) var target: NSRunningApplication?
    private var focused: AXUIElement?
    func capture() -> NSRect? {
        target = NSWorkspace.shared.frontmostApplication; focused = nil
        guard AXIsProcessTrusted(), let target else { return nil }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success, let value else { return nil }
        let element = value as! AXUIElement; focused = element
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success, let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }
        let height = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
    func restore() { if let target, !target.isTerminated { target.activate(options: [.activateIgnoringOtherApps]) } }
    func paste(_ text: String, completion: @escaping (Bool) -> Void) {
        guard AXIsProcessTrusted(), let target, !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { completion(false); return }
        restore()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { completion(false); return }
            if let focused = self.focused {
                var current: CFTypeRef?
                let app = AXUIElementCreateApplication(target.processIdentifier)
                guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &current) == .success,
                      let current, CFEqual(current, focused) else { completion(false); return }
            }
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { completion(false); return }
            let board = NSPasteboard.general
            let saved = board.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
            board.clearContents(); board.setString(text, forType: .string)
            let generation = board.changeCount
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if board.changeCount == generation {
                    board.clearContents()
                    let items = saved.map { entries -> NSPasteboardItem in
                        let item = NSPasteboardItem(); for (type, data) in entries { item.setData(data, forType: type) }; return item
                    }
                    if !items.isEmpty { board.writeObjects(items) }
                }
                completion(true)
            }
        }
    }
}
func showError(_ error: Error) { let alert = NSAlert(error: error); alert.runModal() }
func copyText(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
func button(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton { NSButton(title: title, target: target, action: action) }
func label(_ text: String, size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
    let field = NSTextField(labelWithString: text); field.font = .systemFont(ofSize: size); field.textColor = secondary ? .secondaryLabelColor : .labelColor; return field
}
