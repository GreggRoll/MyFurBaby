import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import sharp from 'sharp';
import { FalAnimations, extractFrames, validateFrames, VIDEO_MODEL, POSE_VIDEO_MODEL, MATTE_MODEL, ANIMATIONS, animationPrompt } from '../animations.js';
import { POSE_MODEL, MOUTH_MODEL, SLEEP_REVISION } from '../sleep-effects.js';
const execute = promisify(execFile);
async function temporary(t) {
  const directory = await mkdtemp(join(tmpdir(), 'fur-animation-test-'));
  t.after(() => rm(directory, { recursive: true, force: true })); return directory;
}
async function rgba(left = 80) {
  const subject = await sharp({ create: { width: 80, height: 80, channels: 4, background: '#800080' } }).png().toBuffer();
  return sharp({ create: { width: 512, height: 512, channels: 4, background: '#00000000' } })
    .composite([{ input: subject, left, top: 160 }]).png().toBuffer();
}
test('fal pipeline preserves original bytes, uses animal alpha mode and reuses completed frames', async t => {
  const directory = await temporary(t), original = await rgba(), calls = [];
  const client = { storage: { upload: async () => 'https://v3.fal.media/reference.png' }, subscribe: async (model, options) => {
    calls.push({ model, input: options.input });
    return { data: (model === VIDEO_MODEL || model === POSE_VIDEO_MODEL) ? { video: { url: 'https://v3.fal.media/generated.mp4' } } : { video: [{ url: 'https://v3.fal.media/transparent.webm' }] }, requestId: 'test' };
  } };
  const animations = new FalAnimations('fake-test-key', directory, { client,
    fetcher: async () => new Response('fake-video'),
    extractor: async (_, directory, duration) => {
      const frames = Array.from({ length: duration * 15 }, (_, i) => `frame_${String(i + 1).padStart(4, '0')}.png`);
      for (const file of frames) await writeFile(join(directory, file), original); return frames;
    } });
  const pet = { id: 'test-pet', image: original.toString('base64') };
  const progress = [];
  const manifest = await animations.generate('playful', pet, update => progress.push(update));
  assert.deepEqual(progress.map(update => update.stage), ['prepare', 'video', 'background', 'frames', 'save', 'completed']);
  assert.deepEqual(progress.map(update => update.completedStages), [0, 1, 2, 3, 4, 5]);
  assert.ok(progress.every(update => update.kind === 'playful' && update.totalStages === 5));
  assert.equal(manifest.frameCount, 45); assert.equal(manifest.fps, 15);
  assert.deepEqual(await readFile(join(directory, pet.id, 'original.png')), original);
  assert.equal(calls[0].input.first_image_url, 'https://v3.fal.media/reference.png');
  assert.equal(calls[0].input.end_image_url, calls[0].input.first_image_url);
  assert.equal(calls[0].input.image_url, undefined);
  assert.equal(manifest.referenceEndpoints, 'same');
  assert.equal(calls[0].model, VIDEO_MODEL); assert.equal(calls[0].input.duration, 3);
  assert.match(calls[0].input.prompt, /Fixed camera/); assert.equal(calls[0].input.generate_multi_clip_switch, false);
  assert.equal(calls[1].model, MATTE_MODEL); assert.equal(calls[1].input.subject_is_person, false); assert.equal(calls[1].input.output_codec, 'vp9');
  assert.deepEqual(await animations.generate('playful', pet), manifest); assert.equal(calls.length, 2);
  assert.equal((await animations.response(pet.id, manifest)).framesBase64.length, 45);
  await assert.rejects(animations.download('http://127.0.0.1/secret', join(directory, 'bad')));
  assert.throws(() => animations.path('../escape', 'run'));
});
test('real VP9 extraction preserves alpha and motion on the same canvas', async t => {
  const directory = await temporary(t), source = join(directory, 'source'), frames = join(directory, 'frames');
  await mkdir(source);
  await writeFile(join(source, 'frame_0001.png'), await rgba(40));
  await writeFile(join(source, 'frame_0002.png'), await rgba(180));
  const video = join(directory, 'transparent.webm');
  await execute(process.env.FFMPEG_PATH ?? 'ffmpeg', ['-hide_banner', '-loglevel', 'error', '-framerate', '15', '-i', join(source, 'frame_%04d.png'), '-c:v', 'libvpx-vp9', '-lossless', '1', '-pix_fmt', 'yuva420p', '-auto-alt-ref', '0', video]);
  const files = await extractFrames(video, frames, 2 / 15);
  assert.equal(files.length, 2);
  const alphas = await Promise.all(files.map(file => sharp(join(frames, file)).extractChannel(3).raw().toBuffer()));
  const firstX = data => { for (let x = 0; x < 512; x++) if (data[170 * 512 + x] > 128) return x; };
  assert.ok(Math.abs(firstX(alphas[0]) - 40) <= 2); assert.ok(Math.abs(firstX(alphas[1]) - 180) <= 2);
  await assert.rejects(validateFrames(frames, 3), /complete/);
  const opaque = await sharp({ create: { width: 512, height: 512, channels: 4, background: '#800080' } }).png().toBuffer();
  await writeFile(join(frames, files[0]), opaque);
  await assert.rejects(validateFrames(frames, 2), /transparency/);
});

test('sleep derives a sleeping seed once and animates it instead of repeating settling', async t => {
  const directory = await temporary(t), original = await rgba(40), sleeping = await rgba(180), prompts = [];
  let renders = 0, finalFailure = true;
  const client = { storage: { upload: async () => 'https://v3.fal.media/reference.png' }, subscribe: async (model, options) => {
    if (model === POSE_MODEL) return { data: { output: '{"pose":"lying on its back belly up","eyes_closed":true,"unknown":false}' }, requestId: 'pose-test' };
    if (model === MOUTH_MODEL) return { data: { points: [{ x: 0.4, y: 0.5 }] }, requestId: 'mouth-test' };
    if ((model === VIDEO_MODEL || model === POSE_VIDEO_MODEL)) {
      prompts.push(options.input.prompt);
      if (prompts.length === 2 && finalFailure) throw new Error('secret-provider-error');
    }
    return { data: (model === VIDEO_MODEL || model === POSE_VIDEO_MODEL) ? { video: { url: 'https://v3.fal.media/generated.mp4' } } : { video: [{ url: 'https://v3.fal.media/transparent.webm' }] }, requestId: 'test' };
  } };
  const animations = new FalAnimations('fake-test-key', directory, { client, fetcher: async () => new Response('fake-video'),
    extractor: async (_, path, duration) => {
      renders++;
      const frames = Array.from({ length: duration * 15 }, (_, i) => `frame_${String(i + 1).padStart(4, '0')}.png`);
      for (const file of frames) await writeFile(join(path, file), sleeping); return frames;
    } });
  const pet = { id: 'sleepy-pet', image: original.toString('base64') };
  const firstProgress = [];
  await assert.rejects(animations.generate('sleep', pet, update => firstProgress.push(update)), error => !error.message.includes('secret'));
  assert.deepEqual(firstProgress.map(update => update.stage), ['prepare', 'sleep_pose_video', 'sleep_pose_background', 'sleep_pose_frames', 'sleep_pose_check', 'video']);
  assert.deepEqual(firstProgress.map(update => update.completedStages), [0, 1, 2, 3, 4, 5]);
  assert.deepEqual(await readFile(join(directory, pet.id, `sleep-reference-v${SLEEP_REVISION}.png`)), sleeping);
  assert.equal(await animations.cached(pet.id, 'sleep'), null);
  finalFailure = false;
  const progress = [];
  const manifest = await animations.generate('sleep', pet, update => progress.push(update));
  assert.deepEqual(progress.map(update => update.stage), ['prepare', 'video', 'background', 'frames', 'verify', 'snore', 'encode', 'save', 'completed']);
  assert.ok(progress.every(update => update.totalStages === 12 && update.kind === 'sleep'));
  assert.deepEqual(progress.map(update => update.completedStages), [0, 5, 6, 7, 8, 9, 10, 11, 12]);
  assert.equal(manifest.sleepPosePrepared, true); assert.equal(manifest.frameCount, 60);
  assert.match(prompts[0], /ON ITS BACK/); assert.match(prompts[1], /VISUAL LOUD SNORING/); assert.match(prompts[2], /VISUAL LOUD SNORING/);
  assert.equal(manifest.behaviorRevision, SLEEP_REVISION); assert.equal(manifest.effects.type, 'floating-zs');
  assert.equal(manifest.effects.mouthPoints.length, 3);
  assert.equal(renders, 2, 'Retry must reuse the saved sleeping seed');
  assert.deepEqual(await readFile(join(directory, pet.id, 'original.png')), original);
  await animations.generate('sleep', pet); assert.equal(prompts.length, 3);
});

test('upright dozing is rejected before caching a sleeping seed', async t => {
  const directory = await temporary(t), original = await rgba(), calls = [];
  const client = { storage: { upload: async () => 'https://v3.fal.media/reference.png' }, subscribe: async model => {
    calls.push(model);
    return { data: model === POSE_MODEL ? { output: '{"pose":"upright","eyes_closed":true}' }
      : (model === VIDEO_MODEL || model === POSE_VIDEO_MODEL) ? { video: { url: 'https://v3.fal.media/generated.mp4' } }
      : { video: [{ url: 'https://v3.fal.media/transparent.webm' }] }, requestId: 'test' };
  } };
  const animations = new FalAnimations('fake-test-key', directory, { client, fetcher: async () => new Response('fake-video'),
    extractor: async (_, path) => { await writeFile(join(path, 'frame_0060.png'), original); return ['frame_0060.png']; } });
  await assert.rejects(animations.generate('sleep', { id: 'upright-pet', image: original.toString('base64') }), /returned/);
  assert.equal(await animations.cached('upright-pet', 'sleep'), null);
  await assert.rejects(readFile(join(directory, 'upright-pet', `sleep-reference-v${SLEEP_REVISION}.png`)));
  assert.deepEqual(calls, [POSE_VIDEO_MODEL, MATTE_MODEL, POSE_MODEL]);
});


test('idle is a two-second endpoint-guided loop with thirty reusable RGBA frames', async t => {
  const directory = await temporary(t), original = await rgba(), calls = [];
  const client = { storage: { upload: async () => 'https://v3.fal.media/idle-reference.png' },
    subscribe: async (model, { input }) => {
      calls.push({ model, input });
      return { data: model === VIDEO_MODEL ? { video: { url: 'https://v3.fal.media/generated.mp4' } }
        : { video: [{ url: 'https://v3.fal.media/transparent.webm' }] }, requestId: 'idle-test' };
    } };
  const animations = new FalAnimations('fake-test-key', directory, { client,
    fetcher: async () => new Response('fake-video'), extractor: async (_, path, duration) => {
      const frames = Array.from({ length: duration * 15 }, (_, i) => `frame_${String(i + 1).padStart(4, '0')}.png`);
      for (const file of frames) await writeFile(join(path, file), original);
      return frames;
    } });
  const result = await animations.generate('idle', { id: 'idle-pet', image: original.toString('base64') });
  assert.equal(result.frameCount, 30); assert.equal(result.duration, 2);
  assert.equal(calls[0].model, VIDEO_MODEL);
  assert.equal(calls[0].input.first_image_url, calls[0].input.end_image_url);
  assert.match(calls[0].input.prompt, /character selection screen/);
  assert.match(calls[0].input.prompt, /Gentle visible breathing/);
  assert.equal((await animations.response('idle-pet', result)).framesBase64.length, 30);
  await animations.generate('idle', { id: 'idle-pet', image: original.toString('base64') });
  assert.equal(calls.length, 2, 'Replaying idle must not regenerate or bill a provider');
});

test('playful prompt chooses a species-appropriate action and makes licking optional', () => {
  assert.equal(ANIMATIONS.playful, 3);
  assert.equal(ANIMATIONS.lick, undefined);
  const prompt = animationPrompt('playful');
  assert.match(prompt, /naturally suits its species, anatomy and personality/);
  assert.match(prompt, /Licking.*only an optional suggestion.*never a requirement/);
  assert.match(prompt, /return precisely to the reference pose/);
  assert.equal(animationPrompt('lick'), prompt);
});

test('legacy paid frames migrate to playful without provider work and keep response bytes', async t => {
  const directory = await temporary(t), legacy = join(directory, 'saved-pet', 'lick');
  await mkdir(legacy, { recursive: true });
  const original = await rgba();
  const frames = Array.from({ length: 45 }, (_, i) => `frame_${String(i + 1).padStart(4, '0')}.png`);
  for (const frame of frames) await writeFile(join(legacy, frame), original);
  const manifest = { version: 1, kind: 'lick', fps: 15, width: 512, height: 512, duration: 3, frameCount: 45, frames };
  await writeFile(join(legacy, 'animation.json'), JSON.stringify(manifest));
  const animations = new FalAnimations('test', directory, { client: { subscribe: async () => { throw new Error('Must reuse saved frames'); } } });
  const [first, concurrent] = await Promise.all([animations.cached('saved-pet', 'playful'), animations.cached('saved-pet', 'playful')]);
  assert.equal(first.kind, 'playful'); assert.deepEqual(concurrent, first);
  const reused = await animations.generate('playful', { id: 'saved-pet' });
  assert.deepEqual(reused, first);
  const oldResponse = await animations.response('saved-pet', manifest);
  assert.equal(oldResponse.kind, 'lick', 'Old clients keep their job contract');
  assert.deepEqual(Buffer.from(oldResponse.framesBase64[0], 'base64'), original);
  assert.equal((await animations.response('saved-pet', reused)).kind, 'playful');
});
