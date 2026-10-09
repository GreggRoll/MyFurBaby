import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { parseSleepingPose, parseMouthPoint, applySnoreEffects, snoreOverlaySVG } from '../sleep-effects.js';

test('sleep accepts reclining anatomy with closed eyes and rejects upright or ambiguous poses', () => {
  assert.equal(parseSleepingPose('{"pose":"back","eyes_closed":true}'), 'back');
  assert.equal(parseSleepingPose('```json\n{"pose":"side","eyes_closed":true}\n```'), 'side');
  assert.equal(parseSleepingPose('{"pose":"lying on its back belly up","eyes_closed":true,"unknown":false}'), 'back');
  assert.equal(parseSleepingPose('{"pose":" Lying on its back, belly up. ","eyes_closed":true}'), 'back');
  assert.equal(parseSleepingPose('{"pose":"fully reclining on its side","eyes_closed":true}'), 'side');
  for (const pose of ['upright', 'unknown']) assert.throws(() => parseSleepingPose(JSON.stringify({ pose, eyes_closed: true })));
  assert.throws(() => parseSleepingPose('{"pose":"side","eyes_closed":false}'));
  for (const pose of ['not lying on its back', 'sitting upright with closed eyes', 'standing', 'back or upright', 'sideways sitting']) {
    assert.throws(() => parseSleepingPose(JSON.stringify({ pose, eyes_closed: true })));
  }
  assert.throws(() => parseSleepingPose('{"pose":"back","eyes_closed":true,"unknown":true}'));
  assert.throws(() => parseSleepingPose('No, the pet is upright.'));
  assert.deepEqual(parseMouthPoint([{ x: 0.4, y: 0.6 }]), { x: 0.4, y: 0.6 });
  for (const points of [[], [{ x: -1, y: 0.5 }], [{ x: 0.3, y: NaN }], [{ x: 0.4, y: 0.5 }, { x: 0.8, y: 0.5 }]]) assert.throws(() => parseMouthPoint(points));
});

test('floating Zs retain RGBA canvas and pet pixels and loop at two seconds', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'fur-snore-test-')); t.after(() => rm(directory, { recursive: true, force: true }));
  const original = await sharp({ create: { width: 512, height: 512, channels: 4, background: '#00000000' } })
    .composite([{ input: await sharp({ create: { width: 120, height: 80, channels: 4, background: '#800080' } }).png().toBuffer(), left: 180, top: 330 }]).png().toBuffer();
  const frames = ['frame_0001.png', 'frame_0002.png', 'frame_0003.png'];
  for (const frame of frames) await writeFile(join(directory, frame), original);
  const effects = await applySnoreEffects(directory, frames, [{ frame: 0, x: 0.3, y: 0.6 }, { frame: 2, x: 0.31, y: 0.6 }]);
  assert.equal(effects.origin, 'tracked-mouth');
  const sourcePixels = await sharp(original).raw().toBuffer();
  const outputs = [];
  for (const frame of frames) {
    const image = sharp(await readFile(join(directory, frame))), metadata = await image.metadata(), output = await image.raw().toBuffer();
    assert.equal(metadata.width, 512); assert.equal(metadata.height, 512); assert.equal(metadata.hasAlpha, true);
    let added = 0;
    for (let i = 0; i < output.length; i += 4) {
      if (sourcePixels[i + 3] > 0) assert.deepEqual(output.subarray(i, i + 4), sourcePixels.subarray(i, i + 4), 'The animal must not move or change');
      if (sourcePixels[i + 3] === 0 && output[i + 3] > 0) added++;
    }
    assert.ok(added > 100, 'Visible letters must survive in the alpha PNG'); outputs.push(output);
  }
  assert.notDeepEqual(outputs[0], outputs[1], 'Letters must move between frames');
  assert.deepEqual(snoreOverlaySVG(0, 15, { x: 0.3, y: 0.6 }), snoreOverlaySVG(30, 15, { x: 0.3, y: 0.6 }));
  await assert.rejects(applySnoreEffects(directory, frames, [{ frame: 1, x: 0.3, y: 0.6 }]));
});
