const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createVimEditor}=require('../Sources/Popaste/Resources/vim-editor.js');
function setup(value){const field={value,selectionStart:0,selectionEnd:0,readOnly:false,setSelectionRange(a,b){this.selectionStart=Math.max(0,Math.min(a,this.value.length));this.selectionEnd=Math.max(0,Math.min(b,this.value.length))}};let changes=0;const editor=createVimEditor(field,{change:()=>changes++});const key=(key,extra={})=>editor.handle({key,preventDefault(){},...extra});editor.setEnabled(true);return {field,editor,key,changes:()=>changes}}
test('normal mode protects text and switches through insert / Escape',()=>{const {field,editor,key}=setup('abc');assert.equal(field.readOnly,true);key('i');assert.equal(editor.mode,'insert');field.value='Xabc';field.setSelectionRange(1,1);assert.equal(key('Escape'),true);assert.equal(editor.mode,'normal');assert.equal(field.selectionStart,0);assert.equal(key('Escape'),false);key('u');assert.equal(field.value,'abc')});
test('grapheme movement and deletion keep emoji and combining marks intact',()=>{const {field,key}=setup('你🌟e\u0301好');key('l');assert.equal(field.selectionStart,1);key('x');assert.equal(field.value,'你e\u0301好');key('l');assert.equal(field.selectionStart,3);key('h');assert.equal(field.selectionStart,1);key('u');assert.equal(field.value,'你🌟e\u0301好')});
test('j/k preserves the desired column across a short line',()=>{const {field,key}=setup('abcdef\nx\nabcdef');key('4');key('l');key('j');assert.equal(field.selectionStart,7);key('j');assert.equal(field.selectionStart,13);key('k');key('k');assert.equal(field.selectionStart,4)});
test('dd, yy, p, undo and redo preserve complete lines',()=>{const {field,key}=setup('one\ntwo\nthree');key('j');key('y');key('y');key('p');assert.equal(field.value,'one\ntwo\ntwo\nthree');key('d');key('d');assert.equal(field.value,'one\ntwo\nthree');key('u');assert.equal(field.value,'one\ntwo\ntwo\nthree');key('r',{ctrlKey:true});assert.equal(field.value,'one\ntwo\nthree')});
test('deleting final line and empty lines is undoable',()=>{const {field,key}=setup('\na\nb');key('d');key('d');assert.equal(field.value,'a\nb');key('j');key('d');key('d');assert.equal(field.value,'a');key('u');assert.equal(field.value,'a\nb')});
test('counted deletion handles consecutive lines',()=>{const {field,key}=setup('a\nb\nc\nd');key('2');key('d');key('d');assert.equal(field.value,'c\nd');key('p');assert.equal(field.value,'c\na\nb\nd')});
test('o opens a new line and groups insertion into one undo',()=>{const {field,key,editor}=setup('first\nlast');key('o');assert.equal(field.value,'first\n\nlast');assert.equal(field.selectionStart,6);field.value='first\nnew\nlast';field.setSelectionRange(9,9);key('Escape');key('u');assert.equal(field.value,'first\nlast');assert.equal(editor.mode,'normal')});
test('IME composition and disabled mode leave keystrokes to textarea',()=>{const {field,key,editor}=setup('你好');assert.equal(key('Escape',{isComposing:true}),false);assert.equal(key('d',{keyCode:229}),false);editor.setEnabled(false);assert.equal(field.readOnly,false);assert.equal(key('j'),false)});
const {visualLineTarget}=require('../Sources/Popaste/Resources/vim-editor.js');
test('visual j/k moves within soft wraps and keeps x across short lines',()=>{
 const points=[{pos:0,x:0,y:0},{pos:1,x:10,y:0},{pos:2,x:20,y:0},{pos:3,x:0,y:20},{pos:4,x:10,y:20},{pos:5,x:20,y:20},{pos:6,x:0,y:40},{pos:7,x:0,y:60},{pos:8,x:10,y:60},{pos:9,x:20,y:60}];
 let result=visualLineTarget(points,2,1);assert.equal(result.target.pos,5);
 result=visualLineTarget(points,5,1,result.x);assert.equal(result.target.pos,6);
 result=visualLineTarget(points,6,1,result.x);assert.equal(result.target.pos,9);
 result=visualLineTarget(points,9,-2,result.x);assert.equal(result.target.pos,5);
 assert.equal(visualLineTarget(points,0,-1).target.pos,0);
});
test('normal j/k delegates counted motion to visual layout',()=>{
 const field={value:'wrapped line',selectionStart:0,selectionEnd:0,setSelectionRange(a,b){this.selectionStart=a;this.selectionEnd=b}};
 const movements=[];const editor=createVimEditor(field,{moveVertical:n=>{movements.push(n);return true}});editor.setEnabled(true);
 for(const key of ['j','3','k'])editor.handle({key,preventDefault(){}});
 assert.deepEqual(movements,[1,-3]);
});
