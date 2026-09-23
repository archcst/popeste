#!/usr/bin/env python3
"""Embed the approved design without its demo data or preview chrome."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
html = (root / 'design/popaste-compact-preview.html').read_text()
html = html.replace('Popaste · 紧凑浮窗设计', 'Popaste')
html = re.sub(r'<script>[\s\S]*?</script>', '', html)
html = re.sub(r' onclick="[^"]*"', '', html)
html = html.replace('<meta charset="utf-8">', '<meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; script-src \'unsafe-inline\'; img-src data:; connect-src \'none\'">')
override = """
html,body{width:100%;height:100%;overflow:hidden;background:transparent}
.board{margin:0;padding:0;max-width:none}.mast,.caption,.legend{display:none!important}
.stage{display:block;min-height:0}.frame{zoom:var(--scale,1);max-width:none}
.window{width:calc(100vw / var(--scale,1));height:calc(100vh / var(--scale,1));max-width:none;box-shadow:none}
.theme-menu{position:absolute;right:17px;top:186px;z-index:5;width:130px;padding:4px;background:var(--paper);border:1px solid var(--line);border-radius:9px;box-shadow:0 6px 20px #0002}.theme-menu[hidden]{display:none}.theme-menu button{display:block;width:100%;text-align:left;padding:8px 10px;border-radius:5px;font-size:12px}
#previewBody{white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.9;padding:15px 18px;overflow:auto;flex:1;font-size:14px}
"""
html = html.replace('</style>', override + '</style>')
script = (root / 'Sources/Popaste/Resources/search-input.js').read_text() + '\n' + (root / 'Sources/Popaste/Resources/interface.js').read_text()
html = html.replace('</html>', '<script>' + script + '</script></html>')
(root / 'Sources/Popaste/Resources/interface.html').write_text(html)
