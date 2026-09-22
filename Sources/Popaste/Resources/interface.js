'use strict';
const $ = id => document.getElementById(id);
const send = (action, payload={}) => window.webkit.messageHandlers.native.postMessage({action,...payload});
const mode = new URLSearchParams(location.hash.slice(1)).get('mode') || 'manager';
document.body.dataset.view = mode;
document.title = 'Popaste';
for(const input of [$('query'),$('body')]){input.spellcheck=false;input.setAttribute('autocorrect','off');input.setAttribute('autocapitalize','off')}
window.nativeFocusEditor = () => $('body').focus();
let state = {prompts:[],body:'',selectedID:null,scale:1}, index=0, preview=false, composing=false, recording=false;
const textLine = body => body.replace(/\s+/g,' ').trim();
const buttons = selector => [...document.querySelectorAll(selector)];
function rows(){const q=$('query').value.toLocaleLowerCase();return state.prompts.filter(p=>q.split(/\s+/).every(w=>p.body.toLocaleLowerCase().includes(w)))}
function element(tag, text, cls){const e=document.createElement(tag);e.textContent=text;if(cls)e.className=cls;return e}
function renderRows(){
 const list=$('otherList');list.replaceChildren();
 state.prompts.forEach(p=>{const b=element('button',textLine(p.body),'side-row'+(p.id===state.selectedID?' active':''));b.title=p.body;b.onclick=()=>send('select',{id:p.id});list.append(b)});
 renderPicker();
}
function renderPicker(){
 const filtered=rows();index=Math.max(0,Math.min(index,filtered.length-1));const list=$('pickerList');list.replaceChildren();
 if(!filtered.length){list.append(element('div',state.prompts.length?'没有匹配的提示词':'还没有提示词，点击 ＋ 创建','empty'));return}
 if(preview){const e=element('div',filtered[index].body);e.id='previewText';list.append(e);return}
 filtered.forEach((p,i)=>{const b=element('button',textLine(p.body),'prompt'+(i===index?' selected':''));b.title=p.body;b.setAttribute('aria-selected',String(i===index));b.onmousedown=e=>e.preventDefault();b.onclick=()=>{index=i;renderPicker();$('query').focus()};b.ondblclick=()=>send('insert',{id:p.id});list.append(b)});
 list.children[index]?.scrollIntoView({block:'nearest'});
}
window.nativeState = next => {
 state=next;document.body.classList.toggle('dark',!!next.dark);
 document.documentElement.style.setProperty('--picker-scale',String(next.scale||1));
 if(mode==='manager'){
  if($('body').value!==next.body)$('body').value=next.body||'';
  $('saveState').textContent=next.status||'已保存到本机';
  $('pinButton').setAttribute('aria-pressed',String(!!next.pinned));
 }
 if(mode==='settings')renderSettings();
 renderRows();
};
window.nativeOpen = () => {index=0;preview=false;$('query').value='';renderPicker();if(mode==='picker')$('query').focus()};
window.nativeToast = text => { $('toast').textContent=text;$('toast').classList.add('show');setTimeout(()=>$('toast').classList.remove('show'),2200) };
function renderSettings(){
 const cards=document.querySelectorAll('.settings-content .pref-card');
 cards[0].replaceChildren();cards[1].replaceChildren();
 const row=(parent,title,description,control)=>{const e=element('div','','pref-row'),copy=element('div','');copy.append(element('strong',title),element('p',description));e.append(copy,control);parent.append(e)};
 const toggle=element('button','','toggle'+(state.login?' on':''));toggle.append(element('i',''));toggle.role='switch';toggle.setAttribute('aria-label','登录时启动');toggle.setAttribute('aria-checked',String(!!state.login));toggle.onclick=()=>send('login',{enabled:!state.login});
 row(cards[0],'登录时启动',state.loginPending?'请在系统设置中批准登录项':'登录 Mac 后，让 Popaste 随时可用',toggle);
 const theme=element('button',state.appearance==='dark'?'深色 ⌄':state.appearance==='light'?'浅色 ⌄':'跟随系统 ⌄','control');theme.onclick=()=>send('appearance',{value:state.appearance==='system'?'light':state.appearance==='light'?'dark':'system'});
 row(cards[0],'外观','选择界面的显示方式',theme);
 const key=element('button',recording?'按下组合键…':state.shortcut,'pref-key');key.onclick=()=>{recording=true;key.textContent='按下组合键…';key.focus()};row(cards[1],'呼出快捷键','在任意输入位置打开提示词浮窗',key);
 const sizes=element('div','','native-setting-size');[['small','小'],['medium','中'],['large','大']].forEach(([value,label])=>{const b=element('button',label);b.setAttribute('aria-pressed',String(state.size===value));b.onclick=()=>send('size',{value});sizes.append(b)});row(cards[1],'浮窗大小','文字、行高与间距同步调整',sizes);
 const permission=element('span',state.trusted?'● 已授权':'尚未授权','pref-status');if(state.trusted)permission.style.color='#6b9479';row(cards[1],'辅助功能权限','用于定位输入光标并粘贴提示词',permission);
 let actions=document.querySelector('.native-actions');if(!actions){actions=element('div','','native-actions');cards[1].after(actions)}actions.replaceChildren();[['授权辅助功能','permission'],['系统设置…','systemSettings'],['刷新状态','refresh']].forEach(([title,action])=>{const b=element('button',title);b.onclick=()=>send(action);actions.append(b)});
 document.querySelector('.pref-footnote').textContent='配置与提示词保存在 ~/.config/popeste';
}
buttons('.action-row').forEach((b,i)=>b.onclick=()=>{
 if(i===0){send('new');return}
 let input=$('managerSearch');
 if(!input){input=document.createElement('input');input.id='managerSearch';input.type='search';input.spellcheck=false;input.setAttribute('autocorrect','off');input.placeholder='搜索提示词…';input.setAttribute('aria-label','搜索提示词');input.className='setting-search';input.style.width='100%';input.oninput=()=>send('search',{query:input.value});b.after(input)}
 input.focus();
});
buttons('.side-bottom button').forEach((b,i)=>b.onclick=()=>send(['import','export','settings'][i]));
$('body').addEventListener('input',()=>{state.body=$('body').value;$('saveState').textContent='有未保存的修改';send('draft',{body:state.body})});
buttons('.save-actions button').forEach((b,i)=>b.onclick=()=>send(i?'save':'cancel',{body:$('body').value}));
$('pinButton').onclick=()=>send('pin');
const more=document.querySelector('[aria-label="更多操作"]');more.onclick=()=>send('export');
document.querySelector('.editor-bottom button').onclick=()=>send('copy',{body:$('body').value});
document.querySelector('.window-footer button').onclick=()=>send('delete');
document.querySelector('.back-button').onclick=()=>send('back');
const settingsSearch=document.querySelector('.settings-nav .setting-search');
if(settingsSearch){
 const input=element('input','');input.type='search';input.spellcheck=false;input.setAttribute('autocorrect','off');input.placeholder='搜索设置…';input.setAttribute('aria-label','搜索设置');settingsSearch.replaceChildren(input);
 input.oninput=()=>{const q=input.value.trim();document.querySelectorAll('.settings-content .pref-row').forEach(row=>row.hidden=!row.textContent.includes(q))};
}
buttons('.settings-nav .side-row').forEach((b,i)=>b.onclick=()=>{
 if(i===2){send('import');return}
 buttons('.settings-nav .side-row').forEach((item,n)=>item.classList.toggle('active',n===i));
 document.querySelector(i===1?'#shortcutCard':'.settings-content h1').scrollIntoView({block:'start'});
});
buttons('.picker-footer button').forEach((b,i)=>b.onclick=()=>send(i?'settings':'new'));
$('query').addEventListener('input',()=>{index=0;preview=false;renderPicker()});
$('query').addEventListener('compositionstart',()=>composing=true);
$('query').addEventListener('compositionend',()=>composing=false);
document.addEventListener('keydown',event=>{
 if(event.isComposing||composing||event.keyCode===229)return;
 if(recording){event.preventDefault();if(event.key==='Escape'){recording=false;renderSettings();return}if(['Alt','Control','Shift','Meta'].includes(event.key))return;send('shortcut',{code:event.code,key:event.key,control:event.ctrlKey,option:event.altKey,command:event.metaKey,shift:event.shiftKey});recording=false;renderSettings();return}
 if(mode==='manager'&&(event.metaKey||event.ctrlKey)&&event.key==='s'){event.preventDefault();send('save',{body:$('body').value});return}
 if(mode!=='picker')return;
 if(event.metaKey&&event.shiftKey&&event.key.toLowerCase()==='c'){event.preventDefault();const p=rows()[index];if(p)send('copy',{body:p.body});return}
 const key=event.key.toLowerCase(),control=event.ctrlKey&&!event.metaKey&&!event.altKey;
 if(key==='escape'){event.preventDefault();send('dismiss');return}
 if(key==='enter'){event.preventDefault();const p=rows()[index];if(p)send('insert',{id:p.id});return}
 if(key==='arrowdown'||(control&&key==='n')){event.preventDefault();index++;renderPicker()}
 if(key==='arrowup'||(control&&key==='p')){event.preventDefault();index--;renderPicker()}
 if(control&&(key==='f'||key==='b')){event.preventDefault();preview=key==='f';renderPicker()}
});
send('ready');
