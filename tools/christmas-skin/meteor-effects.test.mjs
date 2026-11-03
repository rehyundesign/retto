import test from 'node:test';
import assert from 'node:assert/strict';
import { shootingStars, festiveEffects } from './festive-effects.mjs';

test('shooting stars fall down with trails behind them and remain inside the cell', () => {
  for (let frame = 0; frame < 44; frame++) {
    const time = frame * .05;
    for (const star of shootingStars(time)) {
      assert.ok(star.uy > 0 && star.ux < 0);
      assert.ok(star.alpha >= 0 && star.alpha <= 1);
      assert.ok(star.x >= 20 && star.x <= 428 && star.y >= 20 && star.y <= 620);
      const length = Math.min(86, star.travel);
      assert.ok(star.y - star.uy * length <= star.y);
      assert.ok(star.y - star.uy * length >= 20);
    }
  }
  const first = shootingStars(0), later = shootingStars(.1);
  first.forEach((star,i) => { assert.ok(later[i].y > star.y); assert.ok(later[i].x < star.x); });
});

test('completion effect keeps animating on a held character pose in both depth layers', () => {
  const group = { id: 'waving' };
  for (const front of [false,true]) {
    const first = festiveEffects(group, .1, front, 0), later = festiveEffects(group, .4, front, 0);
    assert.notEqual(first, later);
    assert.match(first, /<polygon/);
    assert.doesNotMatch(first, /#83b9cc/);
  }
});
