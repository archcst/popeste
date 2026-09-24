import AppKit
@main struct Review {
 static func key(_ code:UInt16) -> NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)! }
 static func main() throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("assets/screenshots")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  for language in ["en", "zh-Hans"] { for dark in [false,true] { for page in ["list"] {
   let scale = 1.0
   AppText.language = { language }
   let ui = NativeInterface(mode:"list"), window = NSWindow(contentRect:NSRect(x:0,y:0,width:480*scale,height:424*scale),styleMask:.borderless,backing:.buffered,defer:false)
   window.contentView = ui.view
   ui.action = { name,payload in if name == "layout" { window.setContentSize(NSSize(width:480*scale,height:(payload["collapsed"] as? Bool == true ? 57 : 424)*scale)) } }
   ui.state = ["scale":scale,"dark":dark,"language":language,"resolvedLanguage":language,"size":"large","shortcut":"⌃⌥Space","navigationSchemes":["arrows"],"vimEditing":false,"trusted":true,"prompts":[
    ["id":"fixture","body":language == "en" ? "Thanks for the update. I'll take a look and get back to you." : "感谢你的反馈，我会查看后尽快回复。","pinned":true],
    ["id":"fixture2","body":language == "en" ? "Could you share the steps to reproduce this issue?" : "可以分享一下这个问题的复现步骤吗？","pinned":false],
    ["id":"fixture3","body":language == "en" ? "Let's find a time that works for everyone." : "我们找一个大家都方便的时间吧。","pinned":false],
    ["id":"fixture4","body":language == "en" ? "Please review the changes before merging." : "合并之前，请先检查一下这些改动。","pinned":false]
   ]]
   window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
   ui.open("list")
   if page != "collapsed" { _ = ui.handleKey(key(125)) }
   ui.view.layoutSubtreeIfNeeded(); ui.view.displayIfNeeded()
   if let image = ui.view.bitmapImageRepForCachingDisplay(in:ui.view.bounds) {
    ui.view.cacheDisplay(in:ui.view.bounds,to:image)
    try image.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("\(language)-\(dark ? "dark" : "light").png"))
   }
  } } }
  print("Rendered bilingual native screenshots in assets/screenshots")
 }
}
