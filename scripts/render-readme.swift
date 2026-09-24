import AppKit
@main struct Review {
 static func key(_ code:UInt16) -> NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)! }
 static func main() throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("assets/screenshots")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  for language in ["en", "zh-Hans"] { for dark in [false,true] { for page in ["list"] {
   let scale = 0.9
   AppText.language = { language }
   let ui = NativeInterface(mode:"list"), window = NSPanel(contentRect:NSRect(x:0,y:0,width:480*scale,height:424*scale),styleMask:[.borderless, .nonactivatingPanel],backing:.buffered,defer:false)
   let canvas = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
   canvas.isReleasedWhenClosed = false
   canvas.level = .floating
   let backdrop = PreviewBackdrop(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
   backdrop.dark = dark
   canvas.contentView = backdrop
   window.isReleasedWhenClosed = false
   window.isOpaque = false
   window.backgroundColor = .clear
   window.hasShadow = true
   window.level = .popUpMenu
   let surface = GlassSurface(frame: window.contentView!.bounds)
   surface.install(ui.view)
   surface.update(scale: scale, dark: dark, style: "clear")
   window.contentView = surface
   ui.action = { name,payload in if name == "layout" { window.setContentSize(NSSize(width:480*scale,height:(payload["collapsed"] as? Bool == true ? 57 : 424)*scale)) } }
   ui.state = ["scale":scale,"glass":surface.glassEnabled,"glassStyle":"clear","dark":dark,"language":language,"resolvedLanguage":language,"size":"medium","shortcut":"⌃⌥Space","navigationSchemes":["arrows"],"vimEditing":false,"trusted":true,"prompts":[
    ["id":"fixture","body":language == "en" ? "Thanks for the update. I'll take a look and get back to you." : "感谢你的反馈，我会查看后尽快回复。","pinned":true],
    ["id":"fixture2","body":language == "en" ? "Could you share the steps to reproduce this issue?" : "可以分享一下这个问题的复现步骤吗？","pinned":false],
    ["id":"fixture3","body":language == "en" ? "Let's find a time that works for everyone." : "我们找一个大家都方便的时间吧。","pinned":false],
    ["id":"fixture4","body":language == "en" ? "Please review the changes before merging." : "合并之前，请先检查一下这些改动。","pinned":false]
   ]]
   window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
   ui.open("list")
   if page != "collapsed" { _ = ui.handleKey(key(125)) }
   window.setFrameOrigin(NSPoint(x: canvas.frame.midX - window.frame.width / 2, y: canvas.frame.midY - window.frame.height / 2))
   canvas.orderFrontRegardless()
   window.orderFrontRegardless()
   ui.view.layoutSubtreeIfNeeded()
   // Glass needs the window server's composited backdrop; view caching omits it.
   RunLoop.current.run(until: Date().addingTimeInterval(0.7))
   let top = NSScreen.screens[0].frame.maxY
   let rect = canvas.frame
   let capture = Process()
   capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
   capture.arguments = ["-x", "-R\(Int(rect.minX)),\(Int(top-rect.maxY)),\(Int(rect.width)),\(Int(rect.height))", root.appendingPathComponent("\(language)-\(dark ? "dark" : "light")-window.png").path]
   try capture.run()
   capture.waitUntilExit()
   guard capture.terminationStatus == 0 else { throw NSError(domain: "Screenshot", code: Int(capture.terminationStatus)) }
   window.orderOut(nil)
   canvas.orderOut(nil)
  } } }
  print("Rendered bilingual native screenshots in assets/screenshots")
 }
}

/// A controlled desktop backdrop keeps screenshots independent of private windows.
final class PreviewBackdrop: NSView {
 var dark = false
 override func draw(_ dirtyRect: NSRect) {
  let colors: [NSColor] = dark
   ? [NSColor(srgbRed: 0.12, green: 0.18, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.24, green: 0.20, blue: 0.18, alpha: 1)]
   : [NSColor(srgbRed: 0.86, green: 0.92, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.98, green: 0.92, blue: 0.81, alpha: 1)]
  NSGradient(colors: colors)!.draw(in: bounds, angle: -30)
 }
}
