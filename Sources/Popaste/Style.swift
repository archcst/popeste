import AppKit

enum Style {
    static let canvas = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(calibratedWhite: 0.15, alpha: 1) : .white }
    static let sidebar = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1) }
    static let line = NSColor.separatorColor.withAlphaComponent(0.35)
    static let selection = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(calibratedWhite: 0.23, alpha: 1) : NSColor(calibratedWhite: 0.92, alpha: 1) }
}
class Surface: NSView {
    var fill = Style.canvas
    var border: NSColor?
    var radius: CGFloat = 0
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if let border { border.setStroke(); path.lineWidth = 1; path.stroke() }
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
}
final class QuietButton: NSButton {
    var primary = false
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        if primary || isHighlighted {
            (primary ? NSColor.labelColor : Style.selection).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        }
        let color = primary ? Style.canvas : NSColor.labelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: isEnabled ? color : NSColor.disabledControlTextColor]
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8); ring.lineWidth = 2; ring.stroke()
        }
    }
}
@discardableResult func actionButton(_ title: String, target: AnyObject, action: Selector, frame: NSRect, in parent: NSView, primary: Bool = false) -> QuietButton {
    let b = QuietButton(title: title, target: target, action: action); b.frame = frame; b.primary = primary; b.font = .systemFont(ofSize: 13); b.setAccessibilityLabel(title); parent.addSubview(b); return b
}
@discardableResult func textLabel(_ text: String, frame: NSRect, in parent: NSView, size: CGFloat = 13, secondary: Bool = false, weight: NSFont.Weight = .regular) -> NSTextField {
    let field = label(text, size: size, secondary: secondary); field.font = .systemFont(ofSize: size, weight: weight); field.frame = frame; field.lineBreakMode = .byTruncatingTail; parent.addSubview(field); return field
}
func setupWindow(_ window: NSWindow, title: String) -> Surface {
    let desiredSize = window.contentView!.bounds.size
    window.title = title; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView); window.setContentSize(desiredSize); window.isReleasedWhenClosed = false; window.backgroundColor = Style.canvas
    let root = Surface(frame: NSRect(origin: .zero, size: window.contentView!.bounds.size)); window.contentView = root; window.center(); return root
}
final class PromptRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        Style.selection.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 2), xRadius: 9, yRadius: 9).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}
func promptCell(_ prompt: Prompt, width: CGFloat, height: CGFloat, fontSize: CGFloat) -> NSView {
    let cell = Surface(frame: NSRect(x: 0, y: 0, width: width, height: height)); cell.fill = .clear
    let field = textLabel(prompt.excerpt, frame: NSRect(x: 12, y: (height - 20) / 2, width: width - 24, height: 20), in: cell, size: fontSize)
    field.autoresizingMask = [.width]; cell.autoresizingMask = [.width]; cell.setAccessibilityLabel(prompt.body); return cell
}
