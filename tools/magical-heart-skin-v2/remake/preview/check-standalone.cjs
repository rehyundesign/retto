// Execute the standalone HTML's scripts in an isolated DOM test double.
// No browser navigation, URL loading or external resource requests are used.
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),crypto=require('crypto');
const {createCanvas,Image}=require('@napi-rs/canvas');
async function main(){
const html=fs.readFileSync(__dirname+'/index.html','utf8');
assert(!/<script[^>]+src=/.test(html),'Effect renderer must be embedded');
const elements=[];
class Element{
  constructor(tag='div'){this.tag=tag;this.children=[];this.dataset={};this.textContent='';this.attributes={};this.className='';this.classes=new Set();this.classList={toggle:(name,on)=>{if(on===undefined)on=!this.classes.has(name);on?this.classes.add(name):this.classes.delete(name);}};if(tag==='canvas')this.canvas=createCanvas(448,640);elements.push(this);}
  append(...nodes){this.children.push(...nodes);}
  setAttribute(name,value){this.attributes[name]=value;}
  getContext(){return this.canvas.getContext('2d');}
}
const ids={};
for(const match of html.matchAll(/<(\w+)[^>]*\bid="([^"]+)"[^>]*>/g))ids[match[2]]=new Element(match[1]);
for(const match of html.matchAll(/<script id="([^"]+)" type="application\/json">([\s\S]*?)<\/script>/g))ids[match[1]].textContent=match[2];
const main=new Element('main'),backgrounds=['','dark','checker'].map(bg=>{const element=new Element('button');element.dataset.bg=bg;return element;});
const document={getElementById:id=>{assert(ids[id],'Unknown HTML element: '+id);return ids[id];},createElement:tag=>new Element(tag),querySelector:()=>main,querySelectorAll:selector=>selector==='[data-bg]'?backgrounds:selector==='[data-id]'?elements.filter(element=>element.dataset.id):[]};
const callbacks=[];
const sandbox={document,console,Image,performance:{now:()=>0},requestAnimationFrame:callback=>callbacks.push(callback)};
sandbox.window=sandbox;
vm.createContext(sandbox);
for(const match of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g))if(!match[1].includes('application/json'))vm.runInContext(match[2],sandbox);
const loadingStarted=Date.now();while(!callbacks.length&&Date.now()-loadingStarted<3000)await new Promise(resolve=>setTimeout(resolve,5));assert(callbacks.length,'Embedded material textures must decode and start rendering');
assert.equal(ids.states.children.length,8);
assert.equal(ids['drag-controls'].children.length,2);
assert.equal(ids['state-previews'].children.length,8);
assert.equal(ids['drag-previews'].children.length,2);
assert.equal(ids.gallery.children.length,16);
assert.equal(elements.filter(element=>element.canvas).length,22);
const pixels=element=>element.getContext().getImageData(0,0,448,640).data;
const hash=element=>crypto.createHash('sha256').update(pixels(element)).digest('hex');
function tick(time){assert(callbacks.length);callbacks.shift()(time);}
tick(1000);
const front=ids['effect-front'];
const before=hash(front);tick(1300);assert.notEqual(hash(front),before,'Effects must advance');
assert.equal(ids['effect-status'].textContent,'이펙트 재생 중');
ids['pause-effects'].onclick();const held=hash(front);tick(2300);assert.equal(hash(front),held,'Paused effects must hold');
ids['pause-effects'].onclick();tick(2600);assert.notEqual(hash(front),held,'Resume must advance');
ids['toggle-effects'].onclick();tick(2700);
for(const element of elements.filter(element=>element.canvas))assert(pixels(element).every(value=>value===0),'All effect layers must clear when disabled');
ids['toggle-effects'].onclick();tick(3000);
for(const card of [...ids['state-previews'].children,...ids['drag-previews'].children]){
  card.onclick();tick(3300);
  const frame=card.children[0];const [back,,overlay]=frame.children;
  assert(pixels(back).some(value=>value!==0)||pixels(overlay).some(value=>value!==0),'Each state/interaction preview must paint visible effects');
}
assert.equal(ids['effect-status'].textContent,'이펙트 재생 중');
console.log('PASS: standalone inline scripts initialize without external JS; 8 state controls/cards + 2 directional controls/cards; 22 effect canvases paint; play/pause/resume/off/on work. DOM/canvas checks, not browser UI verification.');

}
main().catch(error=>{console.error(error);process.exit(1);});
