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
.window{width:calc(100vw / var(--scale,1));height:calc(100vh / var(--scale,1));max-width:none;box-shadow:none;border-radius:0}
"""
html = html.replace('</style>', override + '</style>')
script = (root / 'Sources/Popaste/Resources/localization.js').read_text() + '\n' + (root / 'Sources/Popaste/Resources/search-input.js').read_text() + '\n' + (root / 'Sources/Popaste/Resources/vim-editor.js').read_text() + '\n' + (root / 'Sources/Popaste/Resources/interface.js').read_text()
html = html.replace('</html>', '<script>' + script + '</script></html>')
(root / 'Sources/Popaste/Resources/interface.html').write_text(html)
