import AppKit
import ApplicationServices

final class Insertion {
    private(set) var target: NSRunningApplication?
    private var focused: AXUIElement?
    func capture() -> NSRect? {
        target = NSWorkspace.shared.frontmostApplication; focused = nil
        guard AXIsProcessTrusted(), let target else { return nil }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        // Chromium can defer its accessibility tree until an assistive client requests it.
        for name in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            var settable = DarwinBoolean(false)
            let attribute = name as CFString
            if AXUIElementIsAttributeSettable(app, attribute, &settable) == .success, settable.boolValue {
                AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue)
            }
        }
        let system = AXUIElementCreateSystemWide()
        guard let element = Self.elementAttribute(app, kAXFocusedUIElementAttribute)
                ?? Self.elementAttribute(system, kAXFocusedUIElementAttribute) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == target.processIdentifier else { return nil }
        focused = element
        // Some controls expose text geometry on their focused child or parent.
        var candidates = [element]
        if let child = Self.elementAttribute(element, kAXFocusedUIElementAttribute) { candidates.insert(child, at: 0) }
        if let parent = Self.elementAttribute(element, kAXParentAttribute) { candidates.append(parent) }
        for candidate in candidates {
            guard let rect = Self.textBounds(candidate) else { continue }
            let height = NSScreen.screens.first?.frame.maxY ?? 0
            let converted = NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
            if NSScreen.screens.contains(where: { $0.frame.intersects(converted.insetBy(dx: -1, dy: -1)) }) { return converted }
        }
        return nil
    }
    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func textBounds(_ element: AXUIElement) -> CGRect? {
        func bounds(_ name: String, _ range: CFTypeRef) -> CGRect? {
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, range, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            let ax = value as! AXValue
            var rect = CGRect.zero
            guard AXValueGetType(ax) == .cgRect, AXValueGetValue(ax, .cgRect, &rect),
                  rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
                  rect.height > 0, rect.width >= 0 else { return nil }
            return rect
        }
        var value: CFTypeRef?
        var selectedBounds: CGRect?
        var selectedRange: CFRange?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXValueGetTypeID() {
            var range = CFRange()
            let ax = value as! AXValue
            if AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range), range.location >= 0 {
                selectedRange = range
                selectedBounds = bounds(kAXBoundsForRangeParameterizedAttribute, value)
                // A zero-length web range may return the entire editor's rectangle.
                // Prefer actual glyph geometry before accepting that result.
                if range.length == 0 {
                    range.length = 1
                    if let one = AXValueCreate(.cfRange, &range),
                       let rect = bounds(kAXBoundsForRangeParameterizedAttribute, one), rect.height <= 40 {
                        return CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height)
                    }
                }
            }
        }
        value = nil
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &value) == .success,
           let value, let rect = bounds("AXBoundsForTextMarkerRange", value), rect.height <= 40 {
            return rect
        }
        if let rect = selectedBounds {
            var count: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count)
            let empty = (count as? NSNumber)?.intValue == 0
            return normalizedInsertionBounds(rect, range: selectedRange, empty: empty)
        }
        return nil
    }
    /// AX coordinates run downward. Empty editors may report their entire height;
    /// use a first-line estimate only when the control confirms there is no text.
    static func normalizedInsertionBounds(_ rect: CGRect, range: CFRange?, empty: Bool) -> CGRect {
        guard empty, let range, range.location == 0, range.length == 0, rect.height > 40 else { return rect }
        return CGRect(x: rect.minX, y: rect.minY, width: 0, height: 22)
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
