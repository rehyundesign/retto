(function(root){const art=typeof module!=='undefined'?require('./sealing-art-v13.js'):root.JeanneSealingArt13;
const clamp=x=>Math.max(0,Math.min(1,x)),smooth=(a,b,x)=>{let q=clamp((x-a)/(b-a));return q*q*(3-2*q)},n=x=>Number(x).toFixed(3),svg=s=>`<svg xmlns="http://www.w3.org/2000/svg" width="224" height="320" viewBox="0 0 224 320">${s}</svg>`;
function render(state,time,frame,attachment,phase){const u=phase===undefined?frame/16:phase;let charge=0,peak=0,release=0;
if(u<.18)charge=smooth(0,.18,u);else if(u<.48){let q=smooth(.18,.48,u);charge=1-q;peak=q;}else if(u<.62)peak=1;else if(u<.84){let q=smooth(.62,.84,u);peak=1-q;release=q;}else release=1-smooth(.84,1,u);
// Independent painted preparation, climax and recovery; no character transforms.
let scene='';for(const [name,o]of [['charge',charge],['peak',peak],['release',release]])if(o>.0001)scene+=`<image href="${art[name]}" width="224" height="320" opacity="${n(o)}"/>`;
const beam=((time/2.4)%1+1)%1,p=.94+.06*Math.sin(time*6),shine=Math.max(charge,peak,release)*.22;
const defs=`<defs><clipPath id="effectDepth13"><path d="M0 0H47.5V205H224V320H0Z"/></clipPath><linearGradient id="flow13"><stop offset="${n(Math.max(0,beam-.16))}" stop-color="black"/><stop offset="${n(beam)}" stop-color="white"/><stop offset="${n(Math.min(1,beam+.16))}" stop-color="black"/></linearGradient><mask id="shimmer13"><rect width="224" height="320" fill="url(#flow13)"/></mask><filter id="pearl13"><feColorMatrix type="matrix" values="1.3 0 0 0 0.08 0 1.3 0 0 0.08 0 0 1.3 0 0.08 0 0 0 1 0"/></filter></defs>`;
const painted=`<g opacity="${n(p)}">${scene}</g><g mask="url(#shimmer13)" filter="url(#pearl13)" opacity="${n(shine)}">${scene}</g>`;
// Same depth order as the approved static image: face and Finn stay unobstructed.
let back=defs+painted,front=defs+`<g clip-path="url(#effectDepth13)">${painted}</g>`;
// A dim live glow remains when a preparation pose is intentionally held.
const x=attachment?.x??98,y=attachment?.y??220,glow=.045+.025*Math.sin(time*4)**2;
const g=`<circle cx="${n(x)}" cy="${n(y)}" r="6" fill="#ffc4df" opacity="${n(glow)}"/>`;back+=g;front+=g;
return {back:svg(back),front:svg(front)};
}root.JeanneSealing13={render};if(typeof module!=='undefined')module.exports=root.JeanneSealing13;})(globalThis);
