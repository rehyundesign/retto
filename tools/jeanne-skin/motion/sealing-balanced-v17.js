(function(root){const art=typeof module!=='undefined'?require('./sealing-art-v13.js'):root.JeanneSealingArt13;
const anchors=typeof module!=='undefined'?require('./sealing-anchors-v14.js').frames:root.SealingAnchors14.frames;const bound=typeof module!=='undefined'?require('./sealing-balanced-art-v17.js'):root.SealingBalancedArt17;
const clamp=x=>Math.max(0,Math.min(1,x)),smooth=(a,b,x)=>{let q=clamp((x-a)/(b-a));return q*q*(3-2*q)},n=x=>Number(x).toFixed(3),svg=s=>`<svg xmlns="http://www.w3.org/2000/svg" width="224" height="320" viewBox="0 0 224 320">${s}</svg>`;
function render(state,time,frame,attachment,phase){const u=frame/16;let charge=0,peak=0,release=0;
if(u<.125)charge=0;else if(u<.25)charge=smooth(.125,.25,u);else if(u<.44){let q=smooth(.25,.44,u);charge=1-q;peak=q;}else if(u<.60)peak=1;else if(u<.76){let q=smooth(.60,.76,u);peak=1-q;release=q;}else release=1-smooth(.76,.92,u);
// Independent painted preparation, climax and recovery; no character transforms.
let scene='';for(const [name,o]of [['charge',charge],['peak',peak],['release',release]])if(o>.0001)scene+=`<image href="${bound[name][frame%16]}" width="224" height="320" opacity="${n(o)}"/>`;
const beam=clamp(u+.008*Math.sin(time*Math.PI/1.2)),p=.985+.015*Math.sin(time*Math.PI/1.2),shine=Math.max(charge,peak,release)*.08;
const defs=`<defs><filter id="soft17" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation=".3"/></filter><filter id="bloom17" x="-8%" y="-8%" width="116%" height="116%"><feGaussianBlur stdDeviation="1.3"/></filter><clipPath id="effectDepth13"><path d="M0 0H47.5V205H224V320H0Z"/></clipPath><linearGradient id="flow13"><stop offset="${n(Math.max(0,beam-.16))}" stop-color="black"/><stop offset="${n(beam)}" stop-color="white"/><stop offset="${n(Math.min(1,beam+.16))}" stop-color="black"/></linearGradient><mask id="shimmer13"><rect width="224" height="320" fill="url(#flow13)"/></mask><filter id="pearl13"><feColorMatrix type="matrix" values="1.3 0 0 0 0.08 0 1.3 0 0 0.08 0 0 1.3 0 0.08 0 0 0 1 0"/></filter></defs>`;
const painted=`<g><g filter="url(#bloom17)" opacity="${n(p*.08)}">${scene}</g><g filter="url(#soft17)" opacity="${n(p*.15)}">${scene}</g><g opacity="${n(p*.85)}">${scene}</g><g mask="url(#shimmer13)" filter="url(#pearl13)" opacity="${n(shine)}">${scene}</g></g>`;
// Same depth order as the approved static image: face and Finn stay unobstructed.
let back=defs+painted,front=defs+`<g clip-path="url(#effectDepth13)">${painted}</g>`;
// A dim live glow remains when a preparation pose is intentionally held.
const x=attachment?.x??98,y=attachment?.y??220,glow=.035+.01*Math.sin(time*Math.PI/1.2)**2;
const g=`<circle cx="${n(x)}" cy="${n(y)}" r="6" fill="#ffc4df" opacity="${n(glow)}"/>`;back+=g;front+=g;
const palm=anchors[frame%16],energy=smooth(.12,.27,u)*(1-smooth(.59,.78,u));
front+=`<defs><radialGradient id="palm14"><stop stop-color="#fffdf5" stop-opacity=".95"/><stop offset=".25" stop-color="#ffe3ee" stop-opacity=".85"/><stop offset=".55" stop-color="#ffb5d5" stop-opacity=".42"/><stop offset="1" stop-color="#ffaacb" stop-opacity="0"/></radialGradient></defs><circle cx="${n(palm.x)}" cy="${n(palm.y)}" r="${n(6+energy*5)}" fill="url(#palm14)" opacity="${n(energy*(.9+.035*Math.sin(time*Math.PI/1.2)**2))}"/>`;
return {back:svg(back),front:svg(front)};
}root.JeanneSealing17={render};if(typeof module!=='undefined')module.exports=root.JeanneSealing17;})(globalThis);
