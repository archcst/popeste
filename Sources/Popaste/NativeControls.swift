import AppKit

final class NativeCanvas: NSView {
    var fill = Style.canvas
    var layoutContent: (() -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func layout() { super.layout(); layoutContent?() }
    override func draw(_ dirtyRect: NSRect) { fill.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        func redraw(_ view: NSView) { view.needsDisplay = true; view.subviews.forEach(redraw) }
        redraw(self)
    }
    override func keyDown(with event: NSEvent) { if keyHandler?(event) != true { super.keyDown(with: event) } }
}
/// Let AppKit draw labels within the inherited glass appearance.
final class NativeLabel: NSTextField {
    override class var cellClass: AnyClass? { get { CenteredLabelCell.self } set {} }
}
final class CenteredLabelCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var result = super.drawingRect(forBounds:rect)
        let height = min(result.height,cellSize(forBounds:rect).height)
        result.origin.y += (result.height-height)/2
        result.size.height = height
        return result
    }
}

final class NativeButton: NSButton {
    var invoke: (() -> Void)?
    var hoverAction: (() -> Void)?
    var dragHandler: ((NSEvent) -> Void)?
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
    var normalFill: NSColor?
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
    override func mouseDown(with event: NSEvent) {
        guard let dragHandler, let window else { super.mouseDown(with:event); return }
        while let next = window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow,from:nil)) { performClick(nil) }
                return
            }
            if hypot(next.locationInWindow.x-event.locationInWindow.x,next.locationInWindow.y-event.locationInWindow.y) >= 4 {
                dragHandler(event); return
            }
        }
    }
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
        if primary || selected || isHighlighted || normalFill != nil {
            let fill = primary ? InterfacePalette.black : (selected || isHighlighted ? selectedFill ?? Style.selection : normalFill ?? .clear)
            fill.setFill()
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
enum RowMarquee {
    static func offset(elapsed: TimeInterval, overflow: CGFloat, scale: CGFloat) -> CGFloat {
        guard overflow > 0, scale > 0 else { return 0 }
        let duration = Double(overflow / (48 * scale))
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: duration + 2)
        return min(overflow, CGFloat(phase) * 48 * scale)
    }
}

final class NativeRow: NSView {
    let body: String
    let tags: [String]
    let tagColors: [String:String]
    let edit: NativeButton
    var selected: Bool
    var choose: (() -> Void)?
    var insert: (() -> Void)?
    var scale: CGFloat
    var glass = false
    private var tracking: NSTrackingArea?
    private var scrollTimer: Timer?
    private var scrollStarted: TimeInterval = 0
    private var scrollOffset: CGFloat = 0
    private var scrollOverflow: CGFloat = 0
    deinit { scrollTimer?.invalidate() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopScrolling() }
    }
    private func stopScrolling() {
        scrollTimer?.invalidate(); scrollTimer = nil; scrollOffset = 0
    }
    private func updateScrolling(overflow: CGFloat) {
        scrollOverflow = overflow
        guard selected, overflow > 0, window?.isVisible == true,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopScrolling(); return
        }
        guard scrollTimer == nil else { scrollOffset = min(scrollOffset, overflow); return }
        scrollStarted = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.selected, self.window?.isVisible == true,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                self.stopScrolling(); self.needsDisplay = true; return
            }
            let next = RowMarquee.offset(elapsed: ProcessInfo.processInfo.systemUptime - self.scrollStarted,
                                         overflow: self.scrollOverflow, scale: self.scale)
            if next != self.scrollOffset { self.scrollOffset = next; self.needsDisplay = true }
        }
        scrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override var isFlipped: Bool { true }
    init(body: String, tags: [String] = [], tagColors: [String:String] = [:], selected: Bool, scale: CGFloat, editAction: @escaping () -> Void) {
        self.body = body.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        self.tags = tags; self.tagColors = tagColors
        self.selected = selected; self.scale = scale
        edit = NativeButton(tr("编辑短语"), symbol: "square.and.pencil", action: editAction)
        super.init(frame: .zero); addSubview(edit); edit.isHidden = true; edit.selected = true; edit.selectedFill = InterfacePalette.paper; edit.cornerSize = 7*scale; edit.muted = true; edit.layoutScale = scale
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel((tags + [self.body]).joined(separator: ": ")); toolTip = tags.joined(separator:", ")
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
        let background = selected ? InterfacePalette.rowSelection : edit.isHidden ? (glass ? .clear : Style.canvas) : InterfacePalette.hover.withAlphaComponent(glass ? 0.55 : 1)
        background.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 10*scale, yRadius: 10*scale).fill()
        let text = NSAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: 17*scale), .foregroundColor: InterfacePalette.ink])
        var area = bounds.insetBy(dx: 12*scale, dy: 0)
        let tagBudget = area.width * 0.45
        var consumed: CGFloat = 0
        for (index, name) in tags.enumerated() {
            let remaining = tagBudget-consumed
            let tagWidth = min((name as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:11*scale)]).width+16*scale,100*scale)
            let overflow = index < tags.count-1 && tagWidth+42*scale > remaining || tagWidth > remaining
            let tag = overflow ? "+\(tags.count-index)" : name
            let colors = InterfacePalette.tagColors(name,custom:tagColors[name.lowercased()])
            let tagText = NSAttributedString(string:tag, attributes:[.font:NSFont.systemFont(ofSize:11*scale), .foregroundColor:colors.text])
            let width = min(tagText.size().width + 16*scale, 100*scale)
            let pill = NSRect(x:area.minX,y:(bounds.height-22*scale)/2,width:width,height:22*scale)
            colors.fill.setFill()
            NSBezierPath(roundedRect:pill,xRadius:11*scale,yRadius:11*scale).fill()
            NSGraphicsContext.saveGraphicsState()
            pill.insetBy(dx:8*scale,dy:0).clip()
            tagText.draw(at:NSPoint(x:pill.minX+8*scale,y:(bounds.height-tagText.size().height)/2))
            NSGraphicsContext.restoreGraphicsState()
            area.origin.x += width+8*scale; area.size.width -= width+8*scale
            consumed += width+8*scale
            if overflow { break }
        }
        NSGraphicsContext.saveGraphicsState(); area.clip()
        let context = NSGraphicsContext.current!.cgContext
        context.beginTransparencyLayer(auxiliaryInfo:nil)
        let visibleWidth = area.width - (edit.isHidden ? 0 : 30*scale)
        let overflow = max(0, text.size().width - visibleWidth)
        updateScrolling(overflow: overflow)
        text.draw(at: NSPoint(x: area.minX-scrollOffset, y: (bounds.height-text.size().height)/2))
        if scrollOffset > 0 {
            let gradient = CGGradient(colorSpace:CGColorSpaceCreateDeviceGray(),colorComponents:[1,0,1,1],locations:[0,1],count:2)!
            context.setBlendMode(.destinationIn)
            context.drawLinearGradient(gradient,start:CGPoint(x:area.minX,y:0),end:CGPoint(x:area.minX+18*scale,y:0),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
            context.setBlendMode(.normal)
        }
        if overflow > scrollOffset + 0.5 {
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
    static func tagColors(_ name: String, custom: String? = nil) -> (text: NSColor, fill: NSColor) {
        if let custom, let normalized = TagColor.normalized(custom), let rgb = UInt32(normalized.dropFirst(),radix:16) {
            func mix(_ target: UInt32, _ fraction: Double) -> UInt32 {
                [0,8,16].reduce(UInt32(0)) { value, shift in
                    value | (UInt32((Double((rgb >> shift)&255)*(1-fraction)+Double((target >> shift)&255)*fraction).rounded()) << shift)
                }
            }
            return (color(mix(0,0.35),mix(0xffffff,0.45)),color(mix(0xffffff,0.87),mix(0,0.65)))
        }
        // A stable hash keeps a tag's color consistent across launches and list orders.
        let hash = name.lowercased().precomposedStringWithCanonicalMapping.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let palette: [(UInt32, UInt32, UInt32, UInt32)] = [
            (0x245db0, 0xe2edff, 0xb7d2ff, 0x233c60), // blue
            (0x087464, 0xdbf3ec, 0x9be5d2, 0x204a43), // teal
            (0x7545a5, 0xefe5fb, 0xdbc0ff, 0x48325f), // violet
            (0xa45512, 0xffedd5, 0xffd29e, 0x573e26), // amber
            (0xa63e65, 0xfbe3ed, 0xffbdd6, 0x5b3045), // rose
            (0x48702a, 0xe8f2da, 0xc9e6a9, 0x364a29)  // green
        ]
        let entry = palette[Int(hash % UInt64(palette.count))]
        return (color(entry.0, entry.2), color(entry.1, entry.3))
    }
    static let ink = NSColor.labelColor
    static let muted = NSColor.secondaryLabelColor
    static let line = color(0xeceef0,0x36393c)
    static let hover = color(0xf5f6f7,0x2d3033)
    static let paper = color(0xffffff,0x242628)
    static let black = color(0x111111,0xf3f4f5)
    static let selected = color(0xeceef0,0x383c40)
    static let rowSelection = color(0xe9ebed,0x494e54)
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

/// A glass selection capsule; the surrounding track stays quiet and transparent.
@available(macOS 26.0, *)
final class GlassSizeSelector: NSView {
    private let thumb = NSGlassEffectView()
    private var buttons: [NativeButton] = []
    private var moving = false
    private(set) var selectedIndex: Int
    private let scale: CGFloat
    private let onSelect: (Int) -> Void
    override var isFlipped: Bool { true }

    init(labels: [String], selected: Int, scale: CGFloat, onSelect: @escaping (Int) -> Void) {
        self.selectedIndex = selected; self.scale = scale; self.onSelect = onSelect
        super.init(frame:.zero)
        wantsLayer = true
        thumb.style = .regular
        let glassContent = NativeCanvas(); glassContent.fill = .clear
        thumb.contentView = glassContent
        if #available(macOS 27.0, *) { thumb.effectIsInteractive = true }
        addSubview(thumb)
        for (index, title) in labels.enumerated() {
            let button = NativeButton(title) { [weak self] in self?.select(index) }
            button.font = .systemFont(ofSize:11*scale)
            button.setAccessibilityRole(.radioButton)
            buttons.append(button); addSubview(button)
        }
        setAccessibilityLabel(tr("浮窗大小"))
        refreshSelection()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func capsuleFrame(_ index: Int) -> NSRect {
        let inset = 2*scale
        let width = (bounds.width-2*inset)/CGFloat(buttons.count)
        return NSRect(x:inset+CGFloat(index)*width,y:inset,width:width,height:bounds.height-2*inset)
    }
    override func layout() {
        super.layout()
        thumb.cornerRadius = (bounds.height-4*scale)/2
        if !moving { thumb.frame = capsuleFrame(selectedIndex) }
        thumb.layoutSubtreeIfNeeded()
        for (index, button) in buttons.enumerated() {
            button.frame = index == selectedIndex ? thumb.contentView!.bounds : capsuleFrame(index)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:bounds.height/2,yRadius:bounds.height/2).fill()
    }
    private func refreshSelection() {
        for (index, button) in buttons.enumerated() {
            if index == selectedIndex {
                thumb.contentView?.addSubview(button)
                button.autoresizingMask = [.width,.height]
                button.frame = thumb.contentView?.bounds ?? .zero
            } else {
                addSubview(button)
                button.autoresizingMask = []
                button.frame = capsuleFrame(index)
            }
            button.inkColor = index == selectedIndex ? .labelColor : .secondaryLabelColor
            button.setAccessibilityValue(index == selectedIndex ? 1 : 0)
            button.needsDisplay = true
        }
    }
    func select(_ index: Int) {
        guard buttons.indices.contains(index), index != selectedIndex, !moving else { return }
        selectedIndex = index; refreshSelection()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            thumb.frame = capsuleFrame(index); onSelect(index); return
        }
        moving = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            thumb.animator().frame = capsuleFrame(index)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.moving = false
            self.onSelect(index)
        }
    }
}

final class TagNameField: NSTextView {
    var stringValue: String { get { string } set { string = newValue } }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = (insertString as? NSAttributedString)?.string ?? (insertString as? String ?? "")
        super.insertText(text.components(separatedBy:.newlines).joined(separator:" "),replacementRange:replacementRange)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { isEditable ? super.hitTest(point) : nil }
}
final class TagNameScroll: NSScrollView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        (documentView as? NSTextView)?.isEditable == true ? super.hitTest(point) : nil
    }
}

/// Selectable capsule with an inline name editor and a hover edit action.
final class NativeTagPill: NSView, NSTextViewDelegate, NSDraggingSource {
    let name: String
    let field = TagNameField(frame:.zero)
    private let textScroll = TagNameScroll()
    let selectButton: NativeButton
    let editButton: NativeButton
    var commit: ((String) -> Void)?
    var cancel: (() -> Void)?
    private(set) var editingName = false
    var didBegin: (() -> Void)?
    private var tracking: NSTrackingArea?
    private let scale: CGFloat
    override var isFlipped: Bool { true }
    init(name: String, selected: Bool, scale: CGFloat, customColor: String? = nil, choose: @escaping () -> Void) {
        self.name = name; self.scale = scale
        selectButton = NativeButton(name, action:choose)
        editButton = NativeButton(tr("重命名标签"),symbol:"square.and.pencil",action:{})
        super.init(frame:.zero)
        let colors = InterfacePalette.tagColors(name,custom:customColor)
        selectButton.font = .systemFont(ofSize:12*scale)
        selectButton.inkColor = colors.text; selectButton.normalFill = colors.fill; selectButton.selectedFill = colors.fill
        selectButton.outline = selected ? colors.text.withAlphaComponent(0.65) : nil
        selectButton.cornerSize = 14*scale; selectButton.alignLeft = true; selectButton.layoutScale = scale
        selectButton.title = ""; selectButton.setAccessibilityLabel(name)
        selectButton.setAccessibilityRole(.radioButton); selectButton.setAccessibilityValue(selected ? 1 : 0)
        editButton.font = .systemFont(ofSize:12*scale); editButton.layoutScale = scale; editButton.iconSize = 12
        editButton.inkColor = colors.text; editButton.isHidden = true
        editButton.normalFill = colors.fill; editButton.selectedFill = colors.fill; editButton.cornerSize = 12*scale
        editButton.invoke = { [weak self] in self?.beginEditing() }
        field.font = selectButton.font; field.textColor = colors.text
        field.drawsBackground = false; field.isRichText = false
        field.textContainerInset = .zero; field.textContainer?.lineFragmentPadding = 0
        field.textContainer?.widthTracksTextView = false
        field.textContainer?.containerSize = NSSize(width:1000000,height:1000)
        field.isHorizontallyResizable = false; field.isVerticallyResizable = false
        field.isAutomaticQuoteSubstitutionEnabled = false; field.isAutomaticDashSubstitutionEnabled = false
        field.insertionPointColor = colors.text
        textScroll.drawsBackground = false; textScroll.borderType = .noBorder
        textScroll.documentView = field
        field.delegate = self; field.stringValue = name; field.isEditable = false; field.isSelectable = false
        field.setAccessibilityLabel(tr("重命名标签"))
        addSubview(selectButton); addSubview(textScroll); addSubview(editButton)
        if !name.isEmpty { selectButton.dragHandler = { [weak self] event in self?.startDragging(event) } }
    }
    required init?(coder:NSCoder) { fatalError() }
    override func layout() {
        super.layout(); selectButton.frame = bounds
        editButton.frame = NSRect(x:bounds.width-25*scale,y:2*scale,width:23*scale,height:24*scale)
        let height = field.layoutManager?.defaultLineHeight(for:field.font!) ?? 17*scale
        let textFrame = NSRect(x:10*scale,y:(bounds.height-height)/2,width:max(20,bounds.width-18*scale),height:height)
        textScroll.frame = backingAlignedRect(textFrame,options:.alignAllEdgesNearest)
        sizeTextDocument()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { if !editingName { editButton.isHidden = false } }
    override func mouseExited(with event:NSEvent) { editButton.isHidden = true }
    func beginEditing() {
        editingName = true; didBegin?(); editButton.isHidden = true
        field.isEditable = true; field.isSelectable = true
        layoutSubtreeIfNeeded(); window?.makeFirstResponder(field)
        field.setSelectedRange(NSRange(location:(field.stringValue as NSString).length,length:0))
    }
    func handleKey(_ event: NSEvent) -> Bool {
        guard !field.hasMarkedText() else { return false }
        if event.keyCode == 36 { finish(true, allowEmpty:true); return true }
        if event.keyCode == 53 { finish(false); return true }
        return false
    }
    private func finish(_ save: Bool, allowEmpty: Bool = false) {
        guard editingName else { return }; editingName = false
        let value = field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        field.isEditable = false; field.isSelectable = false
        field.stringValue = name
        if save && (!value.isEmpty || allowEmpty) { commit?(value) } else { cancel?() }
    }
    private func startDragging(_ event: NSEvent) {
        guard !editingName else { return }
        editButton.isHidden = true
        let item = NSPasteboardItem(); item.setString(name,forType:NativeTagStrip.pasteboardType)
        let drag = NSDraggingItem(pasteboardWriter:item)
        guard let bitmap = bitmapImageRepForCachingDisplay(in:bounds) else { return }
        cacheDisplay(in:bounds,to:bitmap)
        let image = NSImage(size:bounds.size); image.addRepresentation(bitmap)
        drag.setDraggingFrame(bounds,contents:image)
        beginDraggingSession(with:[drag],event:event,source:self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    private func sizeTextDocument() {
        let width = (field.string as NSString).size(withAttributes:[.font:field.font!]).width + 2
        field.setFrameSize(NSSize(width:max(textScroll.contentSize.width,width),height:textScroll.contentSize.height))
    }
    func textDidChange(_ notification:Notification) { sizeTextDocument(); field.scrollRangeToVisible(field.selectedRange()) }
    func textView(_ textView:NSTextView,doCommandBy selector:Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if selector == #selector(NSResponder.insertNewline(_:)) { finish(true, allowEmpty:true); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { finish(false); return true }
        return false
    }
    func textDidEndEditing(_ notification:Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }; self.finish(true)
        }
    }
}


final class NativeTagStrip: NSView {
    static let pasteboardType = NSPasteboard.PasteboardType("app.popaste.tag-order")
    var reorder: (([String]) -> Void)?
    private var insertionX: CGFloat?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame:frame); registerForDraggedTypes([Self.pasteboardType]) }
    required init?(coder:NSCoder) { fatalError() }
    private var pills: [NativeTagPill] { subviews.compactMap { $0 as? NativeTagPill }.filter { !$0.name.isEmpty } }
    private func source(_ info: NSDraggingInfo) -> NativeTagPill? {
        guard let source = info.draggingSource as? NativeTagPill, source.superview === self, !source.editingName else { return nil }
        return source
    }
    private func target(_ info: NSDraggingInfo, source: NativeTagPill) -> NativeTagPill? {
        let x = convert(info.draggingLocation,from:nil).x
        return pills.first { $0 !== source && x < $0.frame.midX }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let source = source(sender) else { return [] }
        if let event = NSApp.currentEvent { _ = autoscroll(with:event) }
        insertionX = target(sender,source:source).map { $0.frame.minX-2 } ?? (pills.last?.frame.maxX ?? bounds.maxX)+2
        needsDisplay = true; return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { insertionX = nil; needsDisplay = true }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { insertionX = nil; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let source = source(sender) else { return false }
        let names = pills.map(\.name)
        let order = TagOrder.moving(source.name,before:target(sender,source:source)?.name,in:names)
        insertionX = nil; needsDisplay = true
        if order != names { reorder?(order) }
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let insertionX else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect:NSRect(x:insertionX-1,y:4,width:2,height:max(0,bounds.height-8)),xRadius:1,yRadius:1).fill()
    }
}
