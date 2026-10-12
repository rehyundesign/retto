import test from 'node:test';
import assert from 'node:assert/strict';
import {festiveEffects,reviewAtmosphere} from './festive-effects.mjs';
import {festiveEffects as previousEffects} from './gen-secondary/before/festive-effects.mjs';

test('review snowfall and garland animate behind a held character and stay within the cell',()=>{
  for(let i=0;i<80;i++){
    const atmosphere=reviewAtmosphere(i*.05);
    for(const p of [...atmosphere.bulbs,...atmosphere.flakes]){
      assert.ok(p.x-p.r>=12&&p.x+p.r<=436&&p.y-p.r>=12&&p.y+p.r<=628);
      assert.ok(p.alpha>=0&&p.alpha<=1);
    }
    // Every pendant remains connected to the quadratic garland by its 8px wire.
    for(const bulb of atmosphere.bulbs){
      const t=(bulb.x-36)/376;
      const curve=(1-t)**2*(155+atmosphere.sway)+2*(1-t)*t*(55+atmosphere.sway)+t*t*(155+atmosphere.sway);
      assert.ok(Math.abs(bulb.y-8-curve)<1e-6);
    }
  }
  assert.notEqual(festiveEffects({id:'review'},.1,false,0),festiveEffects({id:'review'},.3,false,0));
});
test('scope preserves review foreground and all other states including idle and completion',()=>{
  for(const id of ['idle','moveRight','moveLeft','thinking','waiting','failed','jumping','sleeping','waving']){
    for(const time of [0,.1,.4,1.4])for(const front of [false,true])assert.equal(festiveEffects({id},time,front,0),previousEffects({id},time,front,0));
  }
  assert.equal(festiveEffects({id:'review'},.4,true,0),previousEffects({id:'review'},.4,true,0));
});
