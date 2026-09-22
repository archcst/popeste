#!/usr/bin/env python3
"""Embed the approved design without its demo data or preview chrome."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
html = (root / 'design/popaste-preview.html').read_text()
html = re.sub(r'<script>[\s\S]*?</script>', '', html)
html = re.sub(r' onclick="[^"]*"', '', html)
html = html.replace('<meta charset="utf-8">', '<meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; script-src \'unsafe-inline\'; img-src data:; connect-src \'none\'">')
override = '''
html,body{width:100%;height:100%;overflow:hidden;background:transparent}
.board{margin:0;padding:0;max-width:none}.head,.caption,.note,.preview-label{display:none!important}
.grid{zoom:.9;height:calc(100vh / .9);width:calc(100vw / .9)}
.manager{height:calc(100vh / .9);width:calc(100vw / .9);min-height:0;max-height:none;grid-template-columns:260px minmax(0,1fr);border:0;border-radius:0;box-shadow:none}
.traffic{visibility:hidden}.surface.manager{border:0}.editor{padding-top:58px}.sidebar{position:relative}
body[data-view=settings] .settings-content{padding:65px 65px 40px}
body[data-view=picker] .grid{zoom:1;width:100vw;height:100vh}
body[data-view=picker] .grid>section{display:none}
body[data-view=picker] .grid>.left{display:block;position:static;transform:none;zoom:var(--picker-scale,1);width:calc(100vw / var(--picker-scale,1));height:calc(100vh / var(--picker-scale,1))}
body[data-view=picker] .left>section:first-child{height:100%}
body[data-view=picker] .picker{display:flex;flex-direction:column;height:100%;box-shadow:none;border-radius:22px}
body[data-view=picker] .picker-list{flex:1;min-height:0;overflow-y:auto}
.picker .search,.picker-footer{flex-shrink:0}.picker-footer .hints{gap:13px}
#otherList{overflow:auto;flex:1}#pinButton[aria-pressed=true]{background:var(--selected);border-radius:6px}
.native-actions{display:flex;gap:10px;margin-top:18px}.native-actions button{padding:7px 10px;border:1px solid var(--line);border-radius:8px;font-size:12px}
.native-setting-size{display:flex;gap:3px}.native-setting-size button{border:0;background:transparent;padding:8px 13px;border-radius:7px;font-size:13px}.native-setting-size button[aria-pressed=true]{background:var(--selected)}
.pref-row[hidden]{display:none}.setting-search input{width:100%}.toast{z-index:20}.settings-content{overflow:auto}.pref-row .control{white-space:nowrap}
'''
html = html.replace('</style>', override + '</style>')
script = (root / 'Sources/Popaste/Resources/interface.js').read_text()
html = html.replace('</html>', '<script>' + script + '</script></html>')
(root / 'Sources/Popaste/Resources/interface.html').write_text(html)
