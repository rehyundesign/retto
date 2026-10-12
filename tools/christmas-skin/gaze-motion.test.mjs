import test from 'node:test';
import assert from 'node:assert/strict';
import { nextGazeDirection, updateGazeMotion } from './gaze-motion.mjs';

test('all 256 gaze paths use neighboring cuts and the shortest route', () => {
  for (let start = 0; start < 16; start++) for (let target = 0; target < 16; target++) {
    let current = start, steps = 0;
    while (current !== target && steps < 9) {
      const next = nextGazeDirection(current, target);
      assert.ok([1, 15].includes((next - current + 16) % 16));
      current = next; steps++;
    }
    const clockwise = (target - start + 16) % 16;
    assert.equal(current, target);
    assert.equal(steps, Math.min(clockwise, 16 - clockwise));
  }
});

test('hold, pause, slow render, retarget and reset preserve visible intermediate cuts', () => {
  const item = {};
  assert.equal(updateGazeMotion(item, 15, 0), 15);
  assert.equal(updateGazeMotion(item, 4, 0.02), 15);
  assert.equal(updateGazeMotion(item, 4, 0.06), 0);
  assert.equal(updateGazeMotion(item, 4, 0.06), 0);
  assert.equal(updateGazeMotion(item, 4, 3), 1);
  assert.equal(updateGazeMotion(item, 15, 3.07), 0);
  assert.equal(updateGazeMotion(item, null, 3.08), null);
  assert.equal(updateGazeMotion(item, 8, 3.09), 8);
  assert.equal(updateGazeMotion(item, 8, 10), 8);
  assert.equal(updateGazeMotion(item, 10, 10.01), 8);
  assert.equal(updateGazeMotion(item, 10, 10.061), 9);
});
