(function(root){
const locked=typeof module!=='undefined'?require('./effects-checkmate-v6-locked.js'):root.JeanneLatestEffects;
const themed=typeof module!=='undefined'?require('./jeanne-effects-hana-v8.js'):root.JeanneHanaEffects;
const pendant=typeof module!=='undefined'?require('./checkmate-pendant-v9.js'):root.JeanneCheckmatePendant;
function render(state,time,frame,attachment){
 if(state==='review'){
 const e=themed.render(state,time,frame,attachment),light=pendant.render(state,time,frame,attachment);
 const inner=s=>s.replace(/^<svg[^>]*>/,'').replace(/<\/svg>$/,'');
 const svg=s=>`<svg xmlns="http://www.w3.org/2000/svg" width="224" height="320" viewBox="0 0 224 320">${s}</svg>`;
 return {back:svg(`<g transform="scale(.5)">${inner(e.back)}</g>`),front:svg(`<g transform="scale(.5)">${inner(e.front)}</g>`+inner(light.front))};
 }
 const e=themed.render(state,time,frame,attachment),x=attachment?.x??98,y=attachment?.y??220,p=.5+.5*Math.sin(time*Math.PI/2),o=state==='sleeping'?.3:1;
 if(attachment?.visible!==false){const g=`<g transform="translate(${x*2} ${y*2})" opacity="${o}"><circle r="${12+p*5}" fill="#ffb7da" fill-opacity="${.17+p*.15}"/><path d="M-8 0H8M0-8V8" stroke="#fffbe7" stroke-width="1.8" opacity="${.5+p*.5}"/></g>`;e.front=e.front.replace('</svg>',g+'</svg>');}
 e.back=e.back.replace('</svg>',`<circle cx="${355+Math.sin(time*Math.PI/4)*5}" cy="${577+Math.cos(time*Math.PI/4)*5}" r="2.2" fill="#f3cd79" opacity=".45"/></svg>`);
 return e;
}
root.JeanneLatestEffects={render};if(typeof module!=='undefined')module.exports=root.JeanneLatestEffects;
})(globalThis);
