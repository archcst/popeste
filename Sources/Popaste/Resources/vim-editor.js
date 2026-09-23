// A local, plain-text Vim editor. The textarea remains the source of truth.
function createVimEditor(field, callbacks={}) {
 let enabled=false, mode='insert', pending='', count='', register='', undo=[], redo=[], insertStart=null, preferredColumn=null;
 const segmenter=new Intl.Segmenter(undefined,{granularity:'grapheme'});
 const snapshot=()=>({value:field.value,start:field.selectionStart,end:field.selectionEnd});
 function remember(state){if(state.value===field.value)return;undo.push(state);if(undo.length>100)undo.shift();redo=[]}
 function notify(){callbacks.change?.()}
 function setMode(next){callbacks.resetVertical?.();mode=next;field.readOnly=enabled&&mode==='normal';pending='';count='';callbacks.mode?.(enabled?mode:null)}
 function points(text){return [...segmenter.segment(text)].map(s=>s.index).concat(text.length)}
 function lineAt(pos){const text=field.value,start=text.slice(0,pos).lastIndexOf('\n')+1;const end=text.indexOf('\n',pos);return {start,end:end<0?text.length:end}}
 function cursor(pos){const text=field.value;pos=Math.max(0,Math.min(pos,text.length));const line=lineAt(pos);if(pos===line.end&&pos>line.start){const p=points(text.slice(line.start,line.end));pos=line.start+p[p.length-2]}field.setSelectionRange(pos,pos)}
 function finishInsert(){if(insertStart){remember(insertStart);insertStart=null}setMode('normal');const pos=field.selectionStart,line=lineAt(pos);const p=points(field.value.slice(line.start,pos));cursor(pos>line.start?line.start+p[Math.max(0,p.length-2)]:pos)}
 function beginInsert(pos){insertStart=snapshot();setMode('insert');field.setSelectionRange(pos,pos);preferredColumn=null}
 function change(value,pos,before=snapshot()){field.value=value;remember(before);cursor(pos);preferredColumn=null;notify()}
 function restore(state){field.value=state.value;field.setSelectionRange(state.start,state.end);preferredColumn=null;notify()}
 function moveVertical(delta){if(callbacks.moveVertical?.(delta))return;const text=field.value,pos=field.selectionStart,line=lineAt(pos);if(preferredColumn===null)preferredColumn=points(text.slice(line.start,pos)).length-1;let target=line;for(let i=0;i<Math.abs(delta);i++){if(delta>0){if(target.end===text.length)break;target=lineAt(target.end+1)}else{if(!target.start)break;target=lineAt(target.start-1)}}const p=points(text.slice(target.start,target.end));cursor(target.start+p[Math.min(preferredColumn,Math.max(0,p.length-2))])}
 function handle(event){
  if(!enabled||event.isComposing||event.keyCode===229)return false;
  const key=event.key;
  if((event.metaKey&&key.toLowerCase()==='z')||(event.ctrlKey&&key.toLowerCase()==='r')){
   event.preventDefault();if(mode==='insert')finishInsert();const isRedo=event.shiftKey||event.ctrlKey;const from=isRedo?redo:undo,to=isRedo?undo:redo;if(from.length){to.push(snapshot());restore(from.pop())}return true;
  }
  if(mode==='insert'){if(key==='Escape'){event.preventDefault();finishInsert();return true}return false}
  if(key==='Escape'){pending='';count='';return false}
  if(event.metaKey||event.ctrlKey||event.altKey)return false;
  if(['Shift','Control','Alt','Meta','Tab'].includes(key))return false;
  event.preventDefault();
  if(/^[1-9]$/.test(key)||(key==='0'&&count)){count=(count+key).slice(0,4);return true}
  const n=Math.min(999,Number(count)||1);count='';const text=field.value,pos=field.selectionStart,line=lineAt(pos);
  if(pending){const op=pending;pending='';if(key===op){let end=line.end;for(let i=1;i<n&&end<text.length;i++)end=lineAt(end+1).end;register=text.slice(line.start,end)+'\n';if(op==='d'){const after=end<text.length?end+1:end;const start=end===text.length&&line.start>0?line.start-1:line.start;change(text.slice(0,start)+text.slice(after),Math.min(line.start,text.length-(after-start)))}}return true}
  if(key!=='j'&&key!=='k'&&key!=='ArrowDown'&&key!=='ArrowUp'){preferredColumn=null;callbacks.resetVertical?.()}
  switch(key){
   case 'h':case 'ArrowLeft':{const p=points(text.slice(line.start,pos));cursor(line.start+p[Math.max(0,p.length-1-n)]);break}
   case 'l':case 'ArrowRight':{const p=points(text.slice(pos,line.end));cursor(pos+p[Math.min(n,p.length-1)]);break}
   case 'j':case 'ArrowDown':moveVertical(n);break;
   case 'k':case 'ArrowUp':moveVertical(-n);break;
   case '0':cursor(line.start);break;
   case '$':cursor(line.end);break;
   case 'i':beginInsert(pos);break;
   case 'a':{const p=points(text.slice(pos,line.end));beginInsert(pos+(p[1]||0));break}
   case 'I':beginInsert(line.start+(text.slice(line.start,line.end).match(/^\s*/)?.[0].length||0));break;
   case 'A':beginInsert(line.end);break;
   case 'o':case 'O':{const at=key==='o'?line.end:line.start;insertStart=snapshot();field.value=text.slice(0,at)+'\n'+text.slice(at);setMode('insert');field.setSelectionRange(at+(key==='o'?1:0),at+(key==='o'?1:0));notify();break}
   case 'd':case 'y':pending=key;count=n===1?'':String(n);break;
   case 'p':case 'P':if(register){const block=register.repeat(n);if(key==='P')change(text.slice(0,line.start)+block+text.slice(line.start),line.start);else if(line.end<text.length)change(text.slice(0,line.end+1)+block+text.slice(line.end+1),line.end+1);else change(text+'\n'+block.slice(0,-1),text.length+1)}break;
   case 'x':{const p=points(text.slice(pos,line.end));change(text.slice(0,pos)+text.slice(pos+p[Math.min(n,p.length-1)]),pos);break}
   case 'u':for(let i=0;i<n&&undo.length;i++){redo.push(snapshot());restore(undo.pop())}break;
  }
  return true;
 }
 return {handle,reset(){undo=[];redo=[];insertStart=null;preferredColumn=null;setMode(enabled?'normal':'insert')},setEnabled(value){if(enabled===value)return;if(insertStart){remember(insertStart);insertStart=null}enabled=value;setMode(enabled?'normal':'insert')},get mode(){return mode},get enabled(){return enabled}};
}
if(typeof module!=='undefined')module.exports={createVimEditor,visualLineTarget};

// Mirror textarea line wrapping to draw a normal-mode block caret over readonly text.
function installVimCaret(field, isNormal) {
 const host=document.createElement('div');host.className='vim-input';field.replaceWith(host);host.append(field);
 const mirror=document.createElement('div');mirror.className='vim-caret-mirror';mirror.setAttribute('aria-hidden','true');
 const caret=document.createElement('span');caret.className='vim-block-caret';caret.setAttribute('aria-hidden','true');
 host.append(mirror,caret);
 const segmenter=new Intl.Segmenter(undefined,{granularity:'grapheme'});
 let scheduled=false,preferredX=null;
 function prepareMirror(){
  const style=getComputedStyle(field);
  for(const key of ['fontFamily','fontSize','fontWeight','fontStyle','lineHeight','letterSpacing','tabSize','textIndent','wordSpacing','wordBreak','overflowWrap','whiteSpace','padding'])mirror.style[key]=style[key];
  mirror.style.width=field.clientWidth+'px';
  return style;
 }
 function moveVertical(delta){
  if(!field.clientWidth)return false;
  prepareMirror();
  const text=field.value,node=document.createTextNode(text+'\u200b');mirror.replaceChildren(node);
  const scale=field.getBoundingClientRect().width/field.offsetWidth,origin=mirror.getBoundingClientRect();
  const range=document.createRange(),positions=[];
  for(const {index,segment} of segmenter.segment(text+'\u200b')){
   if((segment==='\n'||index===text.length)&&index>0&&text[index-1]!=='\n')continue;
   range.setStart(node,index);range.setEnd(node,index+segment.length);
   const rect=range.getClientRects()[0];if(rect)positions.push({pos:index,x:(rect.left-origin.left)/scale,y:(rect.top-origin.top)/scale,height:rect.height/scale});
  }
  const result=visualLineTarget(positions,field.selectionStart,delta,preferredX);if(!result)return false;
  preferredX=result.x;field.setSelectionRange(result.target.pos,result.target.pos);
  const {y,height}=result.target;
  if(y<field.scrollTop)field.scrollTop=y;
  else if(y+height>field.scrollTop+field.clientHeight)field.scrollTop=y+height-field.clientHeight;
  update();return true;
 }
 function draw(){
  scheduled=false;
  caret.hidden=!isNormal()||document.activeElement!==field||!field.clientWidth;
  if(caret.hidden)return;
  const style=prepareMirror();
  const pos=field.selectionStart,text=field.value;
  const grapheme=[...segmenter.segment(text.slice(pos))][0]?.segment;
  const marker=document.createElement('span');marker.textContent=(!grapheme||grapheme==='\n')?'\u00a0':grapheme;
  mirror.replaceChildren(document.createTextNode(text.slice(0,pos)),marker,document.createTextNode(text.slice(pos+(grapheme?.length||0))));
  const scale=field.getBoundingClientRect().width/field.offsetWidth;
  const origin=mirror.getBoundingClientRect(),rect=marker.getClientRects()[0];if(!rect)return;
  const x=(rect.left-origin.left)/scale,y=(rect.top-origin.top)/scale;
  const height=rect.height/scale,width=Math.max(rect.width/scale,parseFloat(style.fontSize)*.55);
  const ink=mirror.cloneNode(false);
  ink.removeAttribute('class');ink.style.visibility='visible';ink.style.position='absolute';
  ink.style.left=(-x)+'px';ink.style.top=(-y)+'px';ink.textContent=text;
  caret.replaceChildren(ink);
  caret.style.cssText=`left:${x-field.scrollLeft}px;top:${y-field.scrollTop}px;width:${width}px;height:${height}px`;

 }
 function update(){if(!scheduled){scheduled=true;requestAnimationFrame(draw)}}
 for(const event of ['focus','blur','input','keyup','click','scroll'])field.addEventListener(event,update);
 document.addEventListener('selectionchange',update);
 new ResizeObserver(update).observe(field);
 field.addEventListener('pointerdown',()=>{preferredX=null});
 return {update,moveVertical,resetVertical(){preferredX=null}};
}

// Pick the closest horizontal position on the adjacent rendered line.
function visualLineTarget(positions,pos,delta,preferredX=null){
 if(!positions.length)return null;
 const rows=[];
 for(const point of positions){let row=rows.find(row=>Math.abs(row[0].y-point.y)<1);if(!row){row=[];rows.push(row)}row.push(point)}
 rows.sort((a,b)=>a[0].y-b[0].y);
 const current=positions.find(point=>point.pos===pos)||positions.reduce((a,b)=>Math.abs(a.pos-pos)<=Math.abs(b.pos-pos)?a:b);
 const index=rows.findIndex(row=>row.includes(current)),x=preferredX??current.x;
 const row=rows[Math.max(0,Math.min(rows.length-1,index+delta))];
 const target=row.reduce((a,b)=>Math.abs(a.x-x)<=Math.abs(b.x-x)?a:b);
 return {target,x};
}
