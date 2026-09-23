import AppKit

final class NativeCanvas: NSView {
    var fill = Style.canvas
    var layoutContent: (() -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func layout() { super.layout(); layoutContent?() }
    override func draw(_ dirtyRect: NSRect) { fill.setFill(); bounds.fill() }
    override func keyDown(with event: NSEvent) { if keyHandler?(event) != true { super.keyDown(with: event) } }
}
/// Labels and buttons use the same attributed-text metrics in flipped coordinates.
final class NativeLabel: NSTextField {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let text = NSAttributedString(string:stringValue, attributes:[.font:font ?? NSFont.systemFont(ofSize:13), .foregroundColor:textColor ?? NSColor.labelColor])
        let size = text.size()
        let x: CGFloat = alignment == .right ? bounds.width-size.width : alignment == .center ? (bounds.width-size.width)/2 : 0
        NSGraphicsContext.saveGraphicsState(); bounds.clip()
        text.draw(at:NSPoint(x:x,y:(bounds.height-size.height)/2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// NSTextField otherwise top-aligns its field editor inside our taller search row.
final class CenteredSearchCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var result = super.drawingRect(forBounds:rect)
        let height = min(result.height,cellSize(forBounds:rect).height)
        result.origin.y += (result.height-height)/2; result.size.height = height
        return result
    }
    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,start:selStart,length:selLength)
    }
    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame:drawingRect(forBounds:rect),in:view,editor:editor,delegate:delegate,event:event)
    }
}

final class NativeButton: NSButton {
    var invoke: (() -> Void)?
    var hoverAction: (() -> Void)?
    private var hoverTracking: NSTrackingArea?
    var layoutScale: CGFloat?
    var iconSize: CGFloat = 17
    var symbolGap: CGFloat = 7
    var primary = false
    var muted = false
    var symbol: String?
    var selected = false
    var alignRight = false
    var inkColor: NSColor?
    var outline: NSColor?
    var selectedFill: NSColor?
    var cornerSize: CGFloat = 8
    var statusDot = false
    var checkState: Bool?
    var alignLeft = false
    var leadingSymbol: String?
    var trailingSymbol: String?
    override var isFlipped: Bool { true }
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero); self.title = title; self.symbol = symbol; invoke = action
        target = self; self.action = #selector(run); isBordered = false; focusRingType = .none
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func run() { invoke?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        if hoverAction != nil {
            hoverTracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
            addTrackingArea(hoverTracking!)
        }
    }
    override func mouseEntered(with event: NSEvent) { hoverAction?() }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = inkColor ?? (primary ? InterfacePalette.paper : (muted ? InterfacePalette.muted : InterfacePalette.ink))
        if primary || selected || isHighlighted {
            (primary ? InterfacePalette.black : selectedFill ?? Style.selection).setFill()
            NSBezierPath(roundedRect: selectedFill == nil ? bounds.insetBy(dx:1,dy:1) : bounds, xRadius: cornerSize, yRadius: cornerSize).fill()
        }
        if let outline {
            outline.setStroke(); let path = NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:cornerSize,yRadius:cornerSize); path.lineWidth = 1; path.stroke()
        }
        let pointSize = font?.pointSize ?? 13
        let scale = layoutScale ?? pointSize / 13
        func drawSymbol(_ name: String, size: CGFloat, center: NSPoint) {
            CompactIcon.draw(name,in:NSRect(x:center.x-size/2,y:center.y-size/2,width:size,height:size),color:isEnabled ? color : color.withAlphaComponent(0.35))
        }
        if let symbol {
            drawSymbol(symbol,size:iconSize*scale,center:NSPoint(x:bounds.midX,y:bounds.midY))
        } else {
            let text = NSMutableAttributedString(string:title,attributes:[.font:font ?? NSFont.systemFont(ofSize:13),.foregroundColor:isEnabled ? color : color.withAlphaComponent(0.35)])
            let nsTitle = title as NSString
            var start = 0
            while start < nsTitle.length {
                let range = nsTitle.range(of:" / ",range:NSRange(location:start,length:nsTitle.length-start))
                if range.location == NSNotFound { break }
                text.addAttribute(.foregroundColor,value:NSColor.tertiaryLabelColor,range:range); start = NSMaxRange(range)
            }
            let leadingSize: CGFloat = 13*scale
            let trailingSize: CGFloat = (trailingSymbol == "chevron.down" ? 12 : 13)*scale
            let gap = symbolGap*scale
            let leadWidth: CGFloat = checkState != nil ? 18*scale : statusDot ? 12*scale : leadingSymbol != nil ? leadingSize+gap : 0
            let tailWidth: CGFloat = trailingSymbol != nil ? trailingSize+gap : 0
            let width = leadWidth+text.size().width+tailWidth
            let x = alignLeft ? 10*scale : alignRight ? max(0,bounds.width-width-8*scale) : (bounds.width-width)/2
            text.draw(at:NSPoint(x:x+leadWidth,y:(bounds.height-text.size().height)/2))
            if checkState == true { NSAttributedString(string:"✓",attributes:[.font:font ?? NSFont.systemFont(ofSize:12),.foregroundColor:color]).draw(at:NSPoint(x:x,y:(bounds.height-text.size().height)/2)) }
            if statusDot { color.setFill(); NSBezierPath(ovalIn:NSRect(x:x,y:bounds.midY-2.5*scale,width:5*scale,height:5*scale)).fill() }
            if let leadingSymbol { drawSymbol(leadingSymbol,size:leadingSize,center:NSPoint(x:x+leadingSize/2,y:bounds.midY)) }
            if let trailingSymbol { drawSymbol(trailingSymbol,size:trailingSize,center:NSPoint(x:x+width-trailingSize/2,y:bounds.midY)) }

        }
    }
}
final class NativeRow: NSView {
    let body: String
    let edit: NativeButton
    var selected: Bool
    var choose: (() -> Void)?
    var insert: (() -> Void)?
    var scale: CGFloat
    var glass = false
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    init(body: String, selected: Bool, scale: CGFloat, editAction: @escaping () -> Void) {
        self.body = body.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        self.selected = selected; self.scale = scale
        edit = NativeButton(tr("编辑短语"), symbol: "square.and.pencil", action: editAction)
        super.init(frame: .zero); addSubview(edit); edit.isHidden = true; edit.selected = true; edit.selectedFill = InterfacePalette.paper; edit.cornerSize = 7*scale; edit.muted = true; edit.layoutScale = scale
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(self.body)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); edit.frame = NSRect(x: bounds.width-37*scale, y: 7*scale, width: 30*scale, height: 30*scale); edit.font = .systemFont(ofSize: 14*scale) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { edit.isHidden = false; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { edit.isHidden = true; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { choose?(); if event.clickCount == 2 { insert?() } }
    override func accessibilityPerformPress() -> Bool { choose?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        let background = selected ? Style.selection.withAlphaComponent(glass ? 0.65 : 1) : edit.isHidden ? (glass ? .clear : Style.canvas) : InterfacePalette.hover.withAlphaComponent(glass ? 0.55 : 1)
        background.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 10*scale, yRadius: 10*scale).fill()
        let text = NSAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: 17*scale), .foregroundColor: InterfacePalette.ink])
        NSGraphicsContext.saveGraphicsState(); let area = bounds.insetBy(dx: 12*scale, dy: 0); area.clip()
        let context = NSGraphicsContext.current!.cgContext
        context.beginTransparencyLayer(auxiliaryInfo:nil)
        text.draw(at: NSPoint(x: area.minX, y: (bounds.height-text.size().height)/2))
        if text.size().width > area.width || !edit.isHidden {
            let end = edit.isHidden ? bounds.width-10*scale : bounds.width-30*scale
            let gradient = CGGradient(colorSpace:CGColorSpaceCreateDeviceGray(),colorComponents:[1,1,1,0],locations:[0,1],count:2)!
            context.setBlendMode(.destinationIn)
            context.drawLinearGradient(gradient,start:CGPoint(x:end-34*scale,y:0),end:CGPoint(x:end,y:0),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
            context.setBlendMode(.normal)
        }
        context.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class NativeSearch: NSTextField {
    override class var cellClass: AnyClass? { get { CenteredSearchCell.self } set {} }
    var route: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool { route?(event) == true || super.performKeyEquivalent(with: event) }
}

/// Colors and geometry from the approved compact settings design.
enum InterfacePalette {
    static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name:nil) { appearance in
            let value = appearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed:CGFloat((value >> 16) & 255)/255,green:CGFloat((value >> 8) & 255)/255,blue:CGFloat(value & 255)/255,alpha:1)
        }
    }
    static let ink = color(0x303235,0xe8eaec)
    static let muted = color(0x95999e,0x989da3)
    static let line = color(0xeceef0,0x36393c)
    static let hover = color(0xf5f6f7,0x2d3033)
    static let paper = color(0xffffff,0x242628)
    static let black = color(0x111111,0xf3f4f5)
    static let selected = color(0xeceef0,0x383c40)
}
final class SettingsToggle: NSButton {
    var invoke: ((Bool) -> Void)?
    init(_ title: String, enabled: Bool, action: @escaping (Bool) -> Void) {
        super.init(frame:.zero); setButtonType(.switch); self.title = title; state = enabled ? .on : .off
        isBordered = false; focusRingType = .none; invoke = action; target = self; self.action = #selector(changed)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func changed() { invoke?(state == .on) }
    override func draw(_ dirtyRect: NSRect) {
        let scale = bounds.width/30
        (state == .on ? InterfacePalette.black : NSColor(srgbRed:211/255,green:214/255,blue:217/255,alpha:1)).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:9*scale,yRadius:9*scale).fill()
        let dark = effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        (state == .on && dark ? NSColor(srgbRed:37/255,green:38/255,blue:40/255,alpha:1) : .white).setFill()
        NSBezierPath(ovalIn:NSRect(x:(state == .on ? 14 : 2)*scale,y:2*scale,width:14*scale,height:14*scale)).fill()
    }
}

final class SettingsMenuShield: NSView {
    var dismiss: (() -> Void)?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { dismiss?() }
}
