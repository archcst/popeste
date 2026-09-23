const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(require.resolve('../Sources/Popaste/Resources/interface.js'),'utf8');
function setup(){
 const nodes={};const $=id=>nodes[id]??=( {hidden:false,disabled:false,value:'changed',focus(){context.document.activeElement=this},click(){this.onclick?.()}} );
 const context={$,all:()=>['stay','discardChanges','accept'].map($),t:x=>x,view:'editor',editing:{id:'id',body:'original',pinned:false},pinned:false,saving:false,dialogKind:null,leaveAction:null,afterSave:null,previousFocus:null,accept:null,document:{activeElement:null},window:{},prompts:[{id:'id'}],selected:0,searchInput:{reset(){}},sent:[],send:(action,payload)=>context.sent.push({action,payload}),show:next=>{context.view=next},toast:()=>{}};
 $('confirm').hidden=true;context.document.activeElement=$('body');vm.createContext(context);
 vm.runInContext(source.slice(source.indexOf('function dirty()'),source.indexOf('function show(')),context);
 vm.runInContext(source.slice(source.indexOf('function save()'),source.indexOf('function toast(')),context);
 vm.runInContext(source.slice(source.indexOf('window.nativeSaveFailed='),source.indexOf('window.nativeToast=')),context);
 const keyBlock=source.slice(source.indexOf("if(!$('confirm').hidden){"),source.indexOf('if(recording){e.preventDefault()'));
 vm.runInContext('function key(e){'+keyBlock+'}',context);
 const key=key=>context.key({key,preventDefault(){}});
 return {context,$,key};
}
test('Enter waits for save success before leaving the editor',()=>{const {context:c,$,key}=setup();c.navigate('settings');assert.equal($('confirm').hidden,false);key('Enter');assert.equal(c.sent[0].action,'save');assert.equal(c.view,'editor');assert.equal(c.saving,true);c.window.nativeSaved('id');assert.equal(c.view,'settings');assert.equal($('confirm').hidden,true)});
test('failed save retains draft and allows retry',()=>{const {context:c,$,key}=setup();c.navigate('list');key('Enter');c.window.nativeSaveFailed();assert.equal(c.view,'editor');assert.equal($('confirm').hidden,false);assert.equal($('body').value,'changed');key('Enter');assert.equal(c.sent.length,2);c.window.nativeSaved('id');assert.equal(c.view,'list')});
test('Escape returns to editing without saving or discarding',()=>{const {context:c,$,key}=setup();c.navigate('list');key('Escape');assert.equal(c.view,'editor');assert.equal($('body').value,'changed');assert.equal(c.sent.length,0);assert.equal($('confirm').hidden,true);assert.equal($('editor').inert,false)});
test('N leaves without saving and does not insert text',()=>{const {context:c,$,key}=setup();c.navigate('list');key('N');assert.equal(c.view,'list');assert.equal(c.sent.length,0);assert.equal($('body').value,'changed')});
test('empty draft cannot leave via save',()=>{const {context:c,$,key}=setup();$('body').value=' ';c.navigate('list');key('Enter');assert.equal(c.view,'editor');assert.equal(c.sent.length,0);assert.equal($('confirm').hidden,false)});
