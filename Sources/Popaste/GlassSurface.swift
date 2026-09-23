import AppKit

/// One native glass surface for the panel; content remains ordinary AppKit controls.
final class GlassSurface: NSView {
    private var effect: NSView?
    private var content: NSView?
    var glassEnabled: Bool { effect != nil }

    func install(_ content: NSView) {
        self.content = content
        content.autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0
        if #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
           ProcessInfo.processInfo.environment["POPASTE_GLASS"] != "0" {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .clear
            glass.autoresizingMask = [.width, .height]
            glass.contentView = content
            addSubview(glass)
            effect = glass
            layer?.masksToBounds = false
        } else {
            addSubview(content)
            layer?.masksToBounds = true
        }
        content.frame = bounds
    }

    func update(scale: CGFloat, dark: Bool, style: String) {
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        layer?.cornerRadius = 19 * scale
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView {
            glass.style = style == "regular" ? .regular : .clear
            glass.cornerRadius = 19 * scale
        }
    }
}
