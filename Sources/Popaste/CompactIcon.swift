import AppKit

/// The approved design's 24-point outline paths, shared by every native page.
enum CompactIcon {
    static func draw(_ name: String, in rect: NSRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x:rect.minX,y:rect.minY); NSGraphicsContext.current?.cgContext.scaleBy(x:rect.width/24,y:rect.height/24)
        let p = NSBezierPath(); p.lineWidth = 1.5; p.lineCapStyle = .round; p.lineJoinStyle = .round
        func move(_ x:CGFloat,_ y:CGFloat) { p.move(to:NSPoint(x:x,y:y)) }
        func line(_ x:CGFloat,_ y:CGFloat) { p.line(to:NSPoint(x:x,y:y)) }
        switch name {
        case "magnifyingglass": p.appendOval(in:NSRect(x:3.5,y:3.5,width:13,height:13)); move(15,15); line(20,20)
        case "arrow.left": move(10,5); line(3,12); line(10,19); move(3,12); line(20,12)
        case "plus": move(12,5); line(12,19); move(5,12); line(19,12)
        case "slider.horizontal.3":
            move(4,7); line(8,7); move(12,7); line(20,7); move(4,17); line(12,17); move(16,17); line(20,17)
            p.appendOval(in:NSRect(x:8,y:5,width:4,height:4)); p.appendOval(in:NSRect(x:12,y:15,width:4,height:4))
        case "pin": move(8,3); line(16,3); line(15,10); line(18,14); line(6,14); line(9,10); p.close(); move(12,14); line(12,21)
        case "trash": move(4,6); line(20,6); move(9,6); line(9,3); line(15,3); line(15,6); move(6,6); line(7,21); line(17,21); line(18,6); move(10,10); line(10,17); move(14,10); line(14,17)
        case "square.and.pencil":
            move(14,5); line(18,9); move(4,20); line(8,19); line(20,7)
            p.curve(to:NSPoint(x:16,y:3),controlPoint1:NSPoint(x:22.7,y:4.3),controlPoint2:NSPoint(x:18.7,y:0.3)); line(4,15); p.close()
        case "chevron.down": move(6.75,9); line(12,14.25); line(17.25,9); p.lineWidth = 2.25
        case "return": move(19.2,4.8); line(19.2,13.2); line(4.8,13.2); move(9.6,8.4); line(4.8,13.2); line(9.6,18); p.lineWidth = 1.8
        default: break
        }
        color.setStroke(); p.stroke(); NSGraphicsContext.restoreGraphicsState()
    }
}
final class CompactIconView: NSView {
    var name = "magnifyingglass"
    var color = InterfacePalette.muted
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { CompactIcon.draw(name,in:bounds,color:color) }
}
