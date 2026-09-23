
const $=id=>document.getElementById(id), all=s=>[...document.querySelectorAll(s)];
let prompts=[];
let dialogKind=null, leaveAction=null, afterSave=null, previousFocus=null;
let vimCaret;
function updateVimMode(){vimCaret?.update(); $('body').placeholder=vimEditor.enabled?'':t('输入短语正文…'); $('vimMode').textContent=vimEditor.enabled?'Vim · '+t(vimEditor.mode==='normal'?'普通模式':'插入模式'):'' }
const vimEditor=createVimEditor($('body'),{change:()=>{editorState();vimCaret?.update()},mode:()=>updateVimMode(),moveVertical:delta=>vimCaret?.moveVertical(delta),resetVertical:()=>vimCaret?.resetVertical()});
vimCaret=installVimCaret($('body'),()=>vimEditor.enabled&&vimEditor.mode==='normal');

const send=(action,payload={})=>window.webkit.messageHandlers.native.postMessage({action,...payload});
let selected=0, editing=null, pinned=false, view='list', timer, accept=null, recording=false, shortcut='⌥ A', saving=false;
let navigationSchemes=['arrows'];
const navigationKeys={emacs:{down:'n',up:'p',back:'b',forward:'f'},vim:{down:'j',up:'k',back:'h',forward:'l'}};
function navigationKey(event,action){
 if(event.metaKey||event.altKey||event.shiftKey)return false;
 const arrows={down:'ArrowDown',up:'ArrowUp',back:'ArrowLeft',forward:'ArrowRight'};
 return navigationSchemes.some(scheme=>scheme==='arrows'?!event.ctrlKey&&event.key===arrows[action]:event.ctrlKey&&event.key===navigationKeys[scheme][action]);
}
function navigationLabels(action){return navigationSchemes.map(scheme=>scheme==='arrows'?{down:'↓',back:'←'}[action]:'⌃'+navigationKeys[scheme][action].toUpperCase()).join(' / ')}
let listExpanded=false;
function syncLayout(){
 const collapsed=view==='list'&&!listExpanded;
 document.querySelector('.window').classList.toggle('compact',collapsed);
 send('layout',{page:view,collapsed});
}
function expandList(){listExpanded=true;syncLayout();render()}
let composing=false;
document.addEventListener('compositionstart',()=>composing=true);
document.addEventListener('compositionend',()=>composing=false);
const searchInput=createCommittedSearch($('query'),()=>{selected=0;if(searchInput.value.length)expandList();else render()});
function matches(){const q=searchInput.value.toLowerCase().trim();return prompts.filter(p=>q.split(/\s+/).every(w=>p.body.toLowerCase().includes(w)))}
function selectRow(index){
 selected=index;
 all('#rows .prompt-row').forEach((row,i)=>{row.classList.toggle('selected',i===selected);row.querySelector('.row').setAttribute('aria-pressed',String(i===selected))});
 $('query').focus();
}
function updateRowFades(){
 all('#rows .row').forEach(row=>row.classList.toggle('overflowing',row.clientWidth>0&&row.scrollWidth>row.clientWidth));
}
new ResizeObserver(updateRowFades).observe($('rows'));
function render(){
 const rows=matches();selected=Math.max(0,Math.min(selected,rows.length-1));$('rows').replaceChildren();
 rows.forEach((p,i)=>{
  const row=document.createElement('div');row.className='prompt-row'+(i===selected?' selected':'');
  const body=document.createElement('button');body.className='row';body.textContent=p.body.replace(/\s+/g,' ');body.title=p.body;
  body.setAttribute('aria-pressed',String(i===selected));body.onmousedown=e=>e.preventDefault();body.onclick=()=>selectRow(i);
  body.ondblclick=()=>send('insert',{id:p.id});
  const editButton=document.createElement('button');editButton.className='iconbutton row-edit';editButton.title=t('编辑短语（⌘E）');editButton.setAttribute('aria-label',t('编辑短语'));
  editButton.innerHTML='<svg class="icon"><use href="#icon-edit"/></svg>';
  editButton.onclick=e=>{e.stopPropagation();selected=i;edit(p)};
  row.append(body,editButton);$('rows').append(row);
 });
 if(!rows.length){
  const empty=document.createElement('div');empty.className='empty';empty.textContent=prompts.length?t('没有匹配的短语'):t('还没有短语');
  if(!prompts.length){const add=document.createElement('button');add.className='primary';add.textContent=t('新建短语');add.onclick=()=>edit(null);empty.append(add)}
  $('rows').append(empty);
 }
 $('count').textContent=rows.length+(interfaceLanguage==='en'&&rows.length===1?' item':t(' 条'));
 $('rows').children[selected]?.scrollIntoView({block:'nearest'});
 requestAnimationFrame(updateRowFades);
}
function dirty(){return view==='editor'&&($('body').value!==(editing?.body||'')||pinned!==!!editing?.pinned)}
function closeDialog(){
 $('confirm').hidden=true;$('editor').inert=false;dialogKind=null;leaveAction=null;
 if(view==='editor')$('body').focus({preventScroll:true});else previousFocus?.focus();
}
function openDialog(){previousFocus=document.activeElement;$('editor').inert=true;$('confirm').hidden=false;$('stay').focus()}
function dialog(title,description,label,fn){
 dialogKind='delete';$('dialogTitle').textContent=title;$('dialogText').textContent=description;
 $('accept').textContent=label;$('stay').textContent=t('取消');$('discardChanges').hidden=true;accept=fn;openDialog();
}
function confirmLeave(fn){
 dialogKind='unsaved';leaveAction=fn;$('dialogTitle').textContent=t('保存未完成的修改？');$('dialogText').textContent=t('当前修改尚未保存。');
 $('accept').textContent='↵ '+t('保存');$('discardChanges').textContent='N '+t('放弃修改');$('discardChanges').hidden=false;$('stay').textContent='Esc '+t('返回');openDialog();
}
$('stay').onclick=()=>{if(!saving)closeDialog()};
$('discardChanges').onclick=()=>{if(saving)return;const next=leaveAction;closeDialog();next?.()};
$('accept').onclick=()=>{if(dialogKind==='unsaved'){if(!saving){afterSave=leaveAction;if(!save())afterSave=null}}else{const fn=accept;closeDialog();fn?.()}};
function navigate(next,fn){const proceed=()=>{show(next);fn?.()};if(dirty())confirmLeave(proceed);else proceed()}
function show(next){if(view==='editor')send('discard');view=next;if(next==='list')listExpanded=true;syncLayout();recording=false;send('recording',{enabled:false});$('shortcut').textContent=shortcut;all('.page').forEach(e=>e.classList.toggle('active',e.id===next));all('[data-mode]').forEach(e=>e.classList.toggle('active',e.dataset.mode===next));if(next==='list'){render();$('query').focus()}$('caption').replaceChildren();const strong=document.createElement('strong');strong.textContent={list:'一个浮窗，完成常用操作。',editor:'直接编辑正文，保存后回到列表。',settings:'常用设置，一屏放下。',preview:'短语全文'}[next];$('caption').append(strong,document.createElement('br'),{list:'⌘N 新建 · ⌘E 编辑选中项 · ⌘, 设置',editor:'新建、修改、置顶和删除，都留在同一个浮窗里。',settings:'快捷键、语言、外观和配置文件都在这里。',preview:'Ctrl+B 返回列表'}[next])}
function edit(p){
 const scrollTop=view==='preview'?$('previewBody').scrollTop:0;
 navigate('editor',()=>{
  editing=p||null;pinned=!!p?.pinned;$('body').value=p?.body||'';
  $('editorHeading').textContent=p?t('编辑短语'):t('新建短语');$('delete').disabled=!p;editorState();
  vimEditor.reset();$('body').setSelectionRange(0,0);$('body').focus({preventScroll:true});$('body').scrollTop=scrollTop;
 });
}
function editorState(){$('characters').textContent=Array.from($('body').value).length+t(' 字符');$('pin').setAttribute('aria-pressed',String(pinned));$('saveState').textContent=dirty()?t('未保存'):t('已保存');send('draft',{id:editing?.id||'',body:$('body').value,pinned})}
function save(){if(saving)return false;if(!$('body').value.trim()){toast(t('请输入短语正文'));return false}saving=true;$('save').disabled=true;send('save',{id:editing?.id||'',body:$('body').value,pinned});return true}
function toast(text){$('toast').textContent=text;$('toast').classList.add('show');clearTimeout(timer);timer=setTimeout(()=>$('toast').classList.remove('show'),1800)}
$('new').onclick=()=>edit(null);$('settingsButton').onclick=()=>navigate('settings');
all('[data-back]').forEach(b=>b.onclick=()=>navigate('list'));all('[data-mode]').forEach(b=>b.onclick=()=>b.dataset.mode==='editor'?edit(matches()[selected]):navigate(b.dataset.mode));$('body').oninput=editorState;$('pin').onclick=()=>{pinned=!pinned;editorState()};$('save').onclick=save;
$('delete').onclick=()=>dialog(t('删除这条短语？'),t('删除后无法恢复。'),t('删除'),()=>{send('delete',{id:editing.id})});
all('[data-scale]').forEach(b=>b.onclick=()=>send('size',{value:{'0.8':'small','0.9':'medium','1':'large'}[b.dataset.scale]}));
const settingMenus=[];
function makeSelect(id,action,options,multiple=false){
 const button=document.createElement('button');button.id=id;button.className='select-control';button.setAttribute('aria-expanded','false');
 $(id).replaceWith(button);
 const label=document.createElement('span');button.append(label);
 const arrow=document.createElementNS('http://www.w3.org/2000/svg','svg');arrow.setAttribute('viewBox','0 0 16 16');arrow.setAttribute('class','icon chevron');arrow.innerHTML='<path d="m4.5 6 3.5 3.5L11.5 6"/>';button.append(arrow);
 const menu=document.createElement('div');menu.className='setting-menu';menu.hidden=true;button.parentElement.append(menu);
 const control={button,menu,label,options,update(value){
  const values=multiple?value:[value];
  const titles=options.filter(option=>values.includes(option[0])).map(option=>t(option[1]));
  label.replaceChildren();
  titles.forEach((title,index)=>{if(index){const separator=document.createElement('span');separator.className='muted';separator.textContent=' / ';label.append(separator)}label.append(document.createTextNode(title))});
  if(!titles.length)label.textContent='—';menu.replaceChildren();
  for(const [optionValue,title] of options){
   const item=document.createElement('button');const checked=values.includes(optionValue);
   const check=document.createElement('span');check.className='option-check';check.textContent=checked?'✓':'';check.setAttribute('aria-hidden','true');
   item.append(check,document.createTextNode(t(title)));
   if(multiple){item.setAttribute('role','checkbox');item.setAttribute('aria-checked',String(checked))}else item.setAttribute('aria-pressed',String(checked));
   item.onclick=()=>{if(!multiple)control.close();send(action,{value:multiple?(checked?values.filter(v=>v!==optionValue):[...values,optionValue]):optionValue})};menu.append(item)
  }
 },close(){menu.hidden=true;button.setAttribute('aria-expanded','false')}};
 settingMenus.push(control);button.onclick=()=>{const opening=menu.hidden;settingMenus.forEach(m=>m.close());menu.hidden=!opening;button.setAttribute('aria-expanded',String(opening))};
 return control;
}
const keymapControl=makeSelect('keymap','navigationSchemes',[['arrows','↑ ↓ ← →'],['emacs','Emacs'],['vim','Vim']],true);
const appearanceControl=makeSelect('appearance','appearance',[['system','跟随系统'],['light','浅色'],['dark','深色']]);
const languageControl=makeSelect('language','language',[['system','跟随系统'],['zh-Hans','简体中文'],['zh-Hant','繁體中文'],['en','English'],['ja','日本語'],['ko','한국어'],['fr','Français'],['de','Deutsch'],['es','Español']]);
document.addEventListener('click',event=>{settingMenus.forEach(m=>{if(!m.menu.contains(event.target)&&!m.button.contains(event.target))m.close()})});

$('vimEditing').onclick=()=>send('vimEditing',{enabled:$('vimEditing').getAttribute('aria-checked')!=='true'});
$('login').onclick=()=>send('login',{enabled:$('login').getAttribute('aria-checked')!=='true'});
$('permission').onclick=()=>send('permission');$('openDirectory').onclick=()=>send('openDirectory');
$('shortcut').onclick=()=>{recording=true;send('recording',{enabled:true});$('shortcut').textContent=t('按下组合键…')};
document.addEventListener('keydown',e=>{if(composing||searchInput.isComposing||e.isComposing||e.keyCode===229)return;if(e.key==='Escape'){e.preventDefault();e.stopPropagation();}if(e.key==='Escape'&&settingMenus.some(m=>!m.menu.hidden)){settingMenus.forEach(m=>m.close());return;}if(!$('confirm').hidden){
 if(e.key==='Tab'){e.preventDefault();const buttons=all('#confirm button').filter(b=>!b.hidden);const index=buttons.indexOf(document.activeElement);buttons[(index+(e.shiftKey?-1:1)+buttons.length)%buttons.length].focus();return}
 if(e.key==='Escape'){e.preventDefault();if(!saving)closeDialog();return}
 if(dialogKind==='unsaved'&&!e.metaKey&&!e.ctrlKey&&!e.altKey&&(e.key==='Enter'||e.key.toLowerCase()==='n')){e.preventDefault();if(e.key==='Enter')$('accept').click();else $('discardChanges').click();return}
 if(e.metaKey||e.ctrlKey)e.preventDefault();return;
}if(recording){e.preventDefault();if(e.key==='Escape'){recording=false;send('recording',{enabled:false});$('shortcut').textContent=shortcut;return}if(['Meta','Control','Shift','Alt'].includes(e.key))return;if(!(e.metaKey||e.ctrlKey||e.altKey)){toast('请包含 ⌘ / ⌃ / ⌥');return}send('shortcut',{code:e.code,key:e.key,control:e.ctrlKey,option:e.altKey,command:e.metaKey,shift:e.shiftKey});recording=false;send('recording',{enabled:false});return}if(e.metaKey&&!e.ctrlKey&&!e.altKey&&!e.shiftKey){const key=e.key.toLowerCase();if(key==='n'){e.preventDefault();edit(null);return}if(key===','){e.preventDefault();navigate('settings');return}if(key==='e'&&(view==='list'||view==='preview')){e.preventDefault();if(matches()[selected])edit(matches()[selected]);return}}if(view==='editor'&&(e.metaKey||e.ctrlKey)&&e.key==='s'){e.preventDefault();save()}if(view==='editor'&&document.activeElement===$('body')&&vimEditor.handle(e))return;if(e.key==='Escape'){if(view!=='list')navigate('list');else send('dismiss')}if(view==='preview'&&navigationKey(e,'back')){e.preventDefault();show('list')}if(view==='preview'&&e.key==='Enter'&&matches().length){e.preventDefault();send('insert',{id:matches()[selected].id})}if(view==='list'){if(!listExpanded&&(e.key==='Enter'||['down','up','forward'].some(action=>navigationKey(e,action)))){e.preventDefault();selected=0;expandList();return;}if(navigationKey(e,'down')){e.preventDefault();selected++;render()}if(navigationKey(e,'up')){e.preventDefault();selected--;render()}if(e.key==='Enter'&&matches().length){e.preventDefault();send('insert',{id:matches()[selected].id})}if(navigationKey(e,'forward')&&matches().length){e.preventDefault();preview()}if(e.metaKey&&e.shiftKey&&e.key.toLowerCase()==='c'&&matches().length){e.preventDefault();send('copy',{body:matches()[selected].body})}}});render();

for(const el of [$('body'),$('query')]){el.setAttribute('autocorrect','off');el.setAttribute('autocapitalize','off')}
const previewPage=document.createElement('div');previewPage.id='preview';previewPage.className='page';
previewPage.innerHTML='<header class="head"><button class="iconbutton" aria-label="返回短语">←</button><strong>短语</strong><span class="spacer"></span><kbd>⌃B 返回</kbd></header><div class="editor"><textarea id="previewBody" readonly aria-label="短语正文" spellcheck="false"></textarea><div class="editor-meta" aria-hidden="true" style="visibility:hidden"><span>0</span></div></div><footer class="footer"><span class="hint">纯文本</span><span class="spacer"></span><button class="textbutton">编辑</button><button class="primary insert-button"><span>插入</span><svg class="icon" aria-hidden="true" viewBox="0 0 20 20"><path d="M16 4v7H4m4-4-4 4 4 4"/></svg></button></footer>';
document.querySelector('.window').prepend(previewPage);
previewPage.querySelector('.head button').onclick=()=>show('list');previewPage.querySelector('.textbutton').onclick=()=>edit(matches()[selected]);previewPage.querySelector('.primary').onclick=()=>{if(matches()[selected])send('insert',{id:matches()[selected].id})};
function preview(){$('previewBody').value=matches()[selected].body;show('preview');$('previewBody').scrollTop=0}
window.nativeState=next=>{
 interfaceLanguage=next.resolvedLanguage||'zh-Hans';localizeStatic();
 vimEditor.setEnabled(!!next.vimEditing);updateVimMode();$('vimEditing').setAttribute('aria-checked',String(!!next.vimEditing));
 navigationSchemes=next.navigationSchemes||['arrows'];keymapControl.update(navigationSchemes);
 $('expandKeys').textContent=navigationLabels('down')||'↵';
 previewPage.querySelector('kbd').textContent=(navigationLabels('back')||'Esc')+' '+t('返回');
 const selectedID=matches()[selected]?.id;prompts=next.prompts||[];
 const newIndex=matches().findIndex(p=>p.id===selectedID);if(newIndex>=0)selected=newIndex;
 document.documentElement.style.setProperty('--scale',String(next.scale||1));
 document.body.classList.toggle('dark',!!next.dark);
 all('[data-scale]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.scale)===(next.scale||1))));
 appearanceControl.update(next.appearance||'system');languageControl.update(next.language||'system');$('login').setAttribute('aria-checked',String(!!next.login));
 $('login').title=next.loginPending?t('请在系统设置中批准登录项'):'';
 $('permission').textContent=next.trusted?t('已授权 ›'):t('去授权 ›');
 $('permission').style.color=next.trusted?'':'var(--muted)';
 shortcut=next.shortcut||'⌃⌥Space';if(!recording)$('shortcut').textContent=shortcut;
 if(view==='editor'){$('editorHeading').textContent=editing?t('编辑短语'):t('新建短语');editorState()}
 render();
};
window.nativeOpen=destination=>{
 if(['new','edit','settings'].includes(destination)&&(composing||searchInput.isComposing||recording))return;
 if(!$('confirm').hidden&&destination!=='resume')return;
 if(destination==='new'){edit(null);return}
 if(destination==='edit'){if((view==='list'||view==='preview')&&matches()[selected])edit(matches()[selected]);return}
 recording=false;send('recording',{enabled:false});$('shortcut').textContent=shortcut;
 if(destination==='resume'){
  if(view==='list'){searchInput.reset();selected=0;listExpanded=false;syncLayout();render();$('query').focus()}
  else if(view==='editor')$('body').focus();
 }else if(destination==='list'){searchInput.reset();navigate('list');listExpanded=false;syncLayout()}else navigate(destination);
 send('refresh');
};
window.nativeSaveFailed=()=>{saving=false;afterSave=null;$('save').disabled=false};
window.nativeSaved=id=>{const next=afterSave;window.nativeSaveFailed();if(!$('confirm').hidden)closeDialog();editing=null;searchInput.reset();selected=Math.max(0,prompts.findIndex(p=>p.id===id));if(next)next();else show('list');toast(id?t('已保存'):t('已删除'))};
window.nativeToast=toast;

matchMedia('(prefers-color-scheme: dark)').addEventListener('change',()=>send('refresh'));
captureStaticLabels();
send('ready');
