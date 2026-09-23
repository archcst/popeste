
const $=id=>document.getElementById(id), all=s=>[...document.querySelectorAll(s)];
let prompts=[];
const send=(action,payload={})=>window.webkit.messageHandlers.native.postMessage({action,...payload});
let selected=0, editing=null, pinned=false, view='list', timer, accept=null, recording=false, shortcut='⌥ A', saving=false;
const searchInput=createCommittedSearch($('query'),()=>{selected=0;render()});
function matches(){const q=searchInput.value.toLowerCase().trim();return prompts.filter(p=>q.split(/\s+/).every(w=>p.body.toLowerCase().includes(w)))}
function render(){let rows=matches();selected=Math.max(0,Math.min(selected,rows.length-1));$('rows').replaceChildren();rows.forEach((p,i)=>{const b=document.createElement('button');b.className='row'+(i===selected?' selected':'');b.textContent=p.body.replace(/\s+/g,' ');b.title=p.body;b.setAttribute('aria-pressed',String(i===selected));b.onmousedown=e=>e.preventDefault();b.onclick=()=>{selected=i;render();$('query').focus()};b.ondblclick=()=>send('insert',{id:p.id});$('rows').append(b)});if(!rows.length){const e=document.createElement('div');e.className='empty';e.textContent=prompts.length?'没有匹配的提示词':'点击左下角 ＋ 添加提示词';$('rows').append(e)}$('count').textContent=rows.length+' 条';$('edit').disabled=!rows.length;$('rows').children[selected]?.scrollIntoView({block:'nearest'})}
function dirty(){return view==='editor'&&($('body').value!==(editing?.body||'')||pinned!==!!editing?.pinned)}
function dialog(title,description,label,fn){$('dialogTitle').textContent=title;$('dialogText').textContent=description;$('accept').textContent=label;$('stay').textContent=label==='删除'?'取消':'继续编辑';accept=fn;$('confirm').hidden=false}
$('stay').onclick=()=>{$('confirm').hidden=true};$('accept').onclick=()=>{$('confirm').hidden=true;accept?.()};
function navigate(next,fn){if(dirty()){dialog('放弃未保存的修改？','当前修改尚未保存。','放弃修改',()=>{show(next);fn?.()})}else{show(next);fn?.()}}
function show(next){if(view==='editor')send('discard');view=next;recording=false;send('recording',{enabled:false});$('shortcut').textContent=shortcut;all('.page').forEach(e=>e.classList.toggle('active',e.id===next));all('[data-mode]').forEach(e=>e.classList.toggle('active',e.dataset.mode===next));if(next==='list'){render();$('query').focus()}$('caption').replaceChildren();const strong=document.createElement('strong');strong.textContent={list:'一个浮窗，完成常用操作。',editor:'直接编辑正文，保存后回到列表。',settings:'常用设置，一屏放下。',preview:'提示词全文'}[next];$('caption').append(strong,document.createElement('br'),{list:'点底部 ＋ 新建，铅笔编辑，齿轮进入设置。',editor:'新建、修改、置顶和删除，都留在同一个浮窗里。',settings:'快捷键、三档大小、外观和备份都在这里。',preview:'Ctrl+B 返回列表'}[next])}
function edit(p){navigate('editor',()=>{editing=p||null;pinned=!!p?.pinned;$('body').value=p?.body||'';$('editorHeading').textContent=p?'编辑提示词':'新建提示词';$('delete').disabled=!p;editorState();$('body').focus()})}
function editorState(){$('characters').textContent=Array.from($('body').value).length+' 字符';$('pin').setAttribute('aria-pressed',String(pinned));$('saveState').textContent=dirty()?'未保存':'已保存';send('draft',{id:editing?.id||'',body:$('body').value,pinned})}
function save(){if(saving)return;if(!$('body').value.trim()){toast('请输入提示词正文');return}saving=true;$('save').disabled=true;send('save',{id:editing?.id||'',body:$('body').value,pinned})}
function toast(text){$('toast').textContent=text;$('toast').classList.add('show');clearTimeout(timer);timer=setTimeout(()=>$('toast').classList.remove('show'),1800)}
$('new').onclick=()=>edit(null);$('edit').onclick=()=>edit(matches()[selected]);$('settingsButton').onclick=()=>navigate('settings');all('[data-back]').forEach(b=>b.onclick=()=>navigate('list'));all('[data-mode]').forEach(b=>b.onclick=()=>b.dataset.mode==='editor'?edit(matches()[selected]):navigate(b.dataset.mode));$('body').oninput=editorState;$('pin').onclick=()=>{pinned=!pinned;editorState()};$('save').onclick=save;
$('delete').onclick=()=>dialog('删除这条提示词？','删除后无法恢复。','删除',()=>{send('delete',{id:editing.id})});
all('[data-scale]').forEach(b=>b.onclick=()=>send('size',{value:{'0.8':'small','0.9':'medium','1':'large'}[b.dataset.scale]}));
const themeButton=document.createElement('button');themeButton.id='appearance';themeButton.className='shortcut';themeButton.setAttribute('aria-label','外观');themeButton.setAttribute('aria-expanded','false');
$('appearance').replaceWith(themeButton);
const themeMenu=document.createElement('div');themeMenu.className='theme-menu';themeMenu.hidden=true;
for(const [value,label] of [['system','跟随系统'],['light','浅色'],['dark','深色']]){const b=document.createElement('button');b.textContent=label;b.onclick=()=>{themeMenu.hidden=true;themeButton.setAttribute('aria-expanded','false');send('appearance',{value})};themeMenu.append(b)}
document.querySelector('.window').append(themeMenu);
themeButton.onclick=()=>{themeMenu.hidden=!themeMenu.hidden;themeButton.setAttribute('aria-expanded',String(!themeMenu.hidden))};
document.addEventListener('click',event=>{if(!themeMenu.contains(event.target)&&!themeButton.contains(event.target)){themeMenu.hidden=true;themeButton.setAttribute('aria-expanded','false')}});

$('login').onclick=()=>send('login',{enabled:$('login').getAttribute('aria-checked')!=='true'});
$('permission').onclick=()=>send('permission');$('import').onclick=()=>send('import');$('export').onclick=()=>send('export');
$('shortcut').onclick=()=>{recording=true;send('recording',{enabled:true});$('shortcut').textContent='按下组合键…'};
document.addEventListener('keydown',e=>{if(searchInput.isComposing||e.isComposing||e.keyCode===229)return;if(e.key==='Escape'&&!themeMenu.hidden){e.preventDefault();themeMenu.hidden=true;themeButton.setAttribute('aria-expanded','false');return;}if(!$('confirm').hidden){if(e.key==='Escape')$('confirm').hidden=true;return}if(recording){e.preventDefault();if(e.key==='Escape'){recording=false;send('recording',{enabled:false});$('shortcut').textContent=shortcut;return}if(['Meta','Control','Shift','Alt'].includes(e.key))return;if(!(e.metaKey||e.ctrlKey||e.altKey)){toast('请包含 ⌘ / ⌃ / ⌥');return}send('shortcut',{code:e.code,key:e.key,control:e.ctrlKey,option:e.altKey,command:e.metaKey,shift:e.shiftKey});recording=false;send('recording',{enabled:false});return}if(view==='editor'&&(e.metaKey||e.ctrlKey)&&e.key==='s'){e.preventDefault();save()}if(e.key==='Escape'){if(view!=='list')navigate('list');else send('dismiss')}if(view==='preview'&&e.ctrlKey&&e.key==='b'){e.preventDefault();show('list')}if(view==='preview'&&e.key==='Enter'&&matches().length){e.preventDefault();send('insert',{id:matches()[selected].id})}if(view==='list'){if(e.key==='ArrowDown'||e.ctrlKey&&e.key==='n'){e.preventDefault();selected++;render()}if(e.key==='ArrowUp'||e.ctrlKey&&e.key==='p'){e.preventDefault();selected--;render()}if(e.key==='Enter'&&matches().length){e.preventDefault();send('insert',{id:matches()[selected].id})}if(e.ctrlKey&&e.key==='f'&&matches().length){e.preventDefault();preview()}if(e.metaKey&&e.shiftKey&&e.key.toLowerCase()==='c'&&matches().length){e.preventDefault();send('copy',{body:matches()[selected].body})}}});render();

for(const el of [$('body'),$('query')]){el.setAttribute('autocorrect','off');el.setAttribute('autocapitalize','off')}
const previewPage=document.createElement('div');previewPage.id='preview';previewPage.className='page';
previewPage.innerHTML='<header class="head"><button class="iconbutton" aria-label="返回提示词">←</button><strong>提示词</strong><span class="spacer"></span><kbd>⌃B 返回</kbd></header><div id="previewBody"></div><footer class="footer"><span class="hint">纯文本</span><span class="spacer"></span><button class="textbutton">编辑</button><button class="primary">插入</button></footer>';
document.querySelector('.window').prepend(previewPage);
previewPage.querySelector('.head button').onclick=()=>show('list');previewPage.querySelector('.textbutton').onclick=()=>edit(matches()[selected]);previewPage.querySelector('.primary').onclick=()=>{if(matches()[selected])send('insert',{id:matches()[selected].id})};
function preview(){$('previewBody').textContent=matches()[selected].body;show('preview')}
window.nativeState=next=>{
 const selectedID=matches()[selected]?.id;prompts=next.prompts||[];
 const newIndex=matches().findIndex(p=>p.id===selectedID);if(newIndex>=0)selected=newIndex;
 document.documentElement.style.setProperty('--scale',String(next.scale||1));
 document.body.classList.toggle('dark',!!next.dark);
 all('[data-scale]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.scale)===(next.scale||1))));
 $('appearance').textContent=({system:'跟随系统',light:'浅色',dark:'深色'}[next.appearance||'system'])+' ⌄';$('login').setAttribute('aria-checked',String(!!next.login));
 $('login').title=next.loginPending?'请在系统设置中批准登录项':'';
 $('permission').textContent=next.trusted?'已授权 ›':'去授权 ›';
 $('permission').style.color=next.trusted?'':'var(--muted)';
 shortcut=next.shortcut||'⌃⌥Space';if(!recording)$('shortcut').textContent=shortcut;
 render();
};
window.nativeOpen=destination=>{
 recording=false;send('recording',{enabled:false});$('shortcut').textContent=shortcut;
 if(destination==='resume'){
  if(view==='list'){searchInput.reset();selected=0;render();$('query').focus()}
  else if(view==='editor')$('body').focus();
 }else navigate(destination);
 send('refresh');
};
window.nativeSaveFailed=()=>{saving=false;$('save').disabled=false};
window.nativeSaved=id=>{window.nativeSaveFailed();editing=null;searchInput.reset();selected=Math.max(0,prompts.findIndex(p=>p.id===id));show('list');toast(id?'已保存':'已删除')};
window.nativeToast=toast;

matchMedia('(prefers-color-scheme: dark)').addEventListener('change',()=>send('refresh'));
send('ready');
