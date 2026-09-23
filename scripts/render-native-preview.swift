import AppKit
@main struct Review {
 static func key(_ code:UInt16) -> NSEvent { NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)! }
 static func main() throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/ui-review")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  for scale in [0.8,0.9,1.0] { for dark in [false,true] { for page in ["collapsed","list","preview","editor","settings","dialog"] {
   let ui = NativeInterface(mode:"list"), window = NSWindow(contentRect:NSRect(x:0,y:0,width:480*scale,height:424*scale),styleMask:.borderless,backing:.buffered,defer:false)
   window.contentView = ui.view
   ui.action = { name,payload in if name == "layout" { window.setContentSize(NSSize(width:480*scale,height:(payload["collapsed"] as? Bool == true ? 57 : 424)*scale)) } }
   ui.state = ["scale":scale,"dark":dark,"language":"zh-Hans","size":scale == 0.8 ? "small" : scale == 0.9 ? "medium" : "large","shortcut":"⌥A","navigationSchemes":["arrows","emacs","vim"],"vimEditing":false,"trusted":true,"prompts":[["id":"fixture","body":"请把下面的内容整理为简洁清晰的短语。保留中文、英文 Swift 和 emoji 🌟，并核对折行、行距与光标位置。\n第二行保持原有缩进和标点。","pinned":false],["id":"fixture2","body":"感谢你的反馈，我会尽快回复。","pinned":false]]]
   ui.open("list")
   if page != "collapsed" { _ = ui.handleKey(key(125)) }
   if page == "preview" { _ = ui.handleKey(key(124)) }
   if page == "editor" || page == "dialog" { ui.open("edit") }
   if page == "dialog" {
    let editor = ui.view.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NativeEditor }.first!
    editor.insertText("修改 ",replacementRange:NSRange(location:0,length:0)); _ = ui.handleKey(key(53))
   }
   if page == "settings" { ui.open("settings") }
   ui.view.layoutSubtreeIfNeeded(); ui.view.displayIfNeeded()
   if let image = ui.view.bitmapImageRepForCachingDisplay(in:ui.view.bounds) {
    ui.view.cacheDisplay(in:ui.view.bounds,to:image)
    try image.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("\(page)-\(scale)-\(dark ? "dark" : "light").png"))
   }
  } } }
  print("Rendered 36 native fixtures in .build/ui-review")
 }
}
