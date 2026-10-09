import { createFalClient } from '@fal-ai/client';
import sharp from 'sharp';
import { mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createHash } from 'node:crypto';
import { SLEEP_REVISION, POSE_MODEL, MOUTH_MODEL, parseSleepingPose, parseMouthPoint, applySnoreEffects } from './sleep-effects.js';

const execute = promisify(execFile);
export const ANIMATIONS = { playful: 3, run: 4, sleep: 4, idle: 2 };
// Old clients and paid cached jobs keep their identity through the rename.
export const animationKind = kind => kind === 'lick' ? 'playful' : kind;
export const VIDEO_MODEL = 'fal-ai/pixverse/v6/transition';
// Preparing a reclining seed is a one-way pose change, not a playback loop.
export const POSE_VIDEO_MODEL = 'fal-ai/pixverse/v6/image-to-video';
export const MATTE_MODEL = 'veed/video-background-removal';
const failure = 'Animation could not finish. Reserved credits were returned; please try again.';
const sleepLoop = 'The supplied animal is already asleep LYING ON ITS BACK, belly up with paws relaxed, or fully reclining ON ITS SIDE. Preserve this genuine lying-down anatomy; never turn it into an upright sitting or standing animal. Eyes remain completely closed from the first frame to the last. Show exaggerated VISUAL LOUD SNORING: the belly and chest visibly inflate and deflate, the relaxed jaw and cheeks gently vibrate, and the mouth softly opens and closes on each snore. Keep the face and mouth visible and leave generous empty space above the mouth for floating sleep letters added later. No actual text in this video. Keep the entire body on one fixed canvas with minimal repositioning. Preserve the supplied animal’s exact fur, markings, accessories, proportions and style. Fixed camera, stationary plain white background, no zoom, cuts or scene changes. One continuous repeating snore cycle returning to the same reclining pose. Silent video, no audio.';

export function animationPrompt(kind) {
  kind = animationKind(kind);
  if (!Object.hasOwn(ANIMATIONS, kind)) throw new Error('Choose playful, running, sleeping, or idle.');
  const action = {
    idle: 'The pet casually waits in place like an adorable character on a character selection screen. Gentle visible breathing, one soft blink, tiny ear or tail twitches, and a small relaxed weight shift. Sweet, curious and cozy, never aggressive. No big playful actions, walking, running, jumping, fighting or falling asleep. Return precisely to the reference pose at the end for a seamless repeating idle loop.',
    playful: 'The pet performs one short, cheerful playful action that naturally suits its species, anatomy and personality, such as a curious head tilt, a gentle paw bat, a happy wiggle, a small hop, or a playful stretch. Choose a believable action for this particular animal; do not give every species the same behavior. Licking imaginary glass is only an optional suggestion when it makes sense for this animal, never a requirement. Keep the movement friendly and contained, then return precisely to the reference pose for a seamless loop.',
    run: 'The pet rises into a natural playful run, moves a short distance through the canvas, then slows and returns to its starting position and pose. Leave space around the entire animal.',
    sleep: 'The supplied animal gently lies down ON ITS BACK with its belly facing up and paws relaxed, or fully reclines ON ITS SIDE, closes its eyes and falls asleep. End in a genuine horizontal lying-down sleeping pose, NEVER upright sitting or standing and never simply rotate an upright animal. Keep the face and mouth visible and leave empty canvas space above the mouth. No snore letters yet.'
  }[kind];
  return `Animate only the animal in the reference image. Preserve its original appearance, fur colors, markings, accessories, proportions and rendering style. ${action} Fixed camera, stationary plain white background, identical animal markings and proportions, consistent scale, natural continuous movement, no zoom, no cuts, no scene changes, entire animal remains visible. One continuous take. No text, additional animals, floor, scenery or cast shadow. End close to the initial pose when compatible with the action.`;
}

export async function validateFrames(directory, expectedCount, canvas = 512) {
  const frames = (await readdir(directory)).filter(file => /^frame_\d{4}\.png$/.test(file)).sort();
  if (frames.length !== expectedCount) throw new Error('The video did not contain the complete animation.');
  for (const [index, file] of frames.entries()) {
    if (file !== `frame_${String(index + 1).padStart(4, '0')}.png`) throw new Error('Animation frames are incomplete.');
    const image = sharp(await readFile(join(directory, file)));
    const metadata = await image.metadata();
    if (metadata.width !== canvas || metadata.height !== canvas || metadata.channels !== 4 || !metadata.hasAlpha) throw new Error('Animation canvas or alpha channel is invalid.');
    const alpha = await image.clone().extractChannel(3).raw().toBuffer();
    let minimum = 255, maximum = 0;
    for (const value of alpha) { minimum = Math.min(minimum, value); maximum = Math.max(maximum, value); }
    if (minimum === 255 || maximum === 0) throw new Error('Animation transparency or subject is missing.');
  }
  return frames;
}

export async function extractFrames(video, directory, duration, { canvas = 512, fps = 15, ffmpeg = process.env.FFMPEG_PATH ?? 'ffmpeg' } = {}) {
  await mkdir(directory, { recursive: true });
  // Check the decoded source alpha before padding, which could otherwise disguise an opaque source.
  const { stdout: alpha } = await execute(ffmpeg, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-c:v', 'libvpx-vp9', '-i', video,
    '-vf', 'alphaextract', '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'gray', 'pipe:1'],
  { timeout: 120_000, maxBuffer: 16_777_216, encoding: 'buffer' });
  if (!alpha.some(value => value < 255) || !alpha.some(value => value > 0)) throw new Error('Video transparency or subject is missing.');
  // One constant scale/pad transform for the whole clip. Never trim, track, or center a subject per frame.
  await execute(ffmpeg, ['-hide_banner', '-loglevel', 'error', '-nostdin', '-y', '-c:v', 'libvpx-vp9', '-i', video,
    '-an', '-vf', `fps=${fps},scale=${canvas}:${canvas}:force_original_aspect_ratio=decrease,format=rgba,pad=${canvas}:${canvas}:(ow-iw)/2:(oh-ih)/2:color=0x00000000`,
    '-frames:v', String(duration * fps), '-pix_fmt', 'rgba', join(directory, 'frame_%04d.png')], { timeout: 120_000, maxBuffer: 1_000_000 });
  return validateFrames(directory, duration * fps, canvas);
}

export class FalAnimations {
  constructor(key, directory, { client, fetcher = fetch, extractor = extractFrames } = {}) {
    this.key = key; this.directory = resolve(directory); this.client = client ?? createFalClient({ credentials: key });
    this.fetch = fetcher; this.extract = extractor;
    this.inFlight = new Map();
  }
  path(petID, kind) {
    kind = animationKind(kind);
    if (!/^[a-zA-Z0-9-]{1,100}$/.test(petID) || !Object.hasOwn(ANIMATIONS, kind)) throw new Error('Invalid animation.');
    return join(this.directory, petID, kind);
  }
  async cached(petID, kind) {
    kind = animationKind(kind);
    try {
      const directory = this.path(petID, kind);
      if (kind === 'playful') {
        // Rename the complete legacy cache once, without another provider call.
        try { await readFile(join(directory, 'animation.json')); }
        catch (error) {
          if (error.code !== 'ENOENT') throw error;
          try { await rename(join(this.directory, petID, 'lick'), directory); }
          catch (migrationError) {
            // Another read may have completed this migration while we awaited IO.
            await readFile(join(directory, 'animation.json'));
          }
        }
      }
      const manifest = JSON.parse(await readFile(join(directory, 'animation.json'), 'utf8'));
      manifest.kind = animationKind(manifest.kind);
      const frames = await validateFrames(directory, ANIMATIONS[kind] * 15);
      if (manifest.version !== 1 || (kind === 'sleep' && (!manifest.sleepPosePrepared || manifest.behaviorRevision !== SLEEP_REVISION || manifest.effects?.type !== 'floating-zs')) || manifest.fps !== 15 || manifest.width !== 512 || manifest.height !== 512 || manifest.kind !== kind || JSON.stringify(manifest.frames) !== JSON.stringify(frames)) return null;
      return manifest;
    } catch { return null; }
  }
  async response(petID, manifest) {
    const kind = animationKind(manifest.kind);
    if (kind === 'playful') await this.cached(petID, kind);
    const directory = this.path(petID, kind);
    const framesBase64 = [];
    for (const file of manifest.frames) {
      if (!/^frame_\d{4}\.png$/.test(file)) throw new Error(failure);
      framesBase64.push((await readFile(join(directory, file))).toString('base64'));
    }
    return { ...manifest, framesBase64 };
  }
  // Compatibility for older apps that only understand a two-by-two sheet.
  async pose(kind, pet) {
    const manifest = await this.generate(kind, pet), directory = this.path(pet.id, kind);
    const input = await Promise.all(Array.from({ length: 4 }, (_, index) => readFile(join(directory, manifest.frames[Math.floor(index * manifest.frames.length / 4)]))));
    const sheet = await sharp({ create: { width: 1024, height: 1024, channels: 4, background: '#00000000' } })
      .composite(input.map((value, index) => ({ input: value, left: index % 2 * 512, top: Math.floor(index / 2) * 512 }))).png().toBuffer();
    return { image: sheet.toString('base64'), usage: { providers: manifest.providers, requestIDs: manifest.requestIDs } };
  }
  async download(url, filename) {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || !(parsed.hostname.endsWith('.fal.media') || parsed.hostname === 'fal.media' || parsed.hostname === 'storage.googleapis.com')) throw new Error(failure);
    const response = await this.fetch(url, { redirect: 'error', signal: AbortSignal.timeout(120_000) });
    if (!response.ok || Number(response.headers.get('content-length')) > 100_000_000) throw new Error(failure);
    let size = 0; const chunks = [];
    for await (const chunk of response.body) { size += chunk.length; if (size > 100_000_000) throw new Error(failure); chunks.push(chunk); }
    await writeFile(filename, Buffer.concat(chunks));
  }
  async generate(kind, pet, onProgress = () => {}) {
    kind = animationKind(kind);
    const key = this.path(pet.id, kind);
    if (this.inFlight.has(key)) return this.inFlight.get(key);
    const pending = this.build(kind, pet, onProgress);
    this.inFlight.set(key, pending);
    try { return await pending; }
    finally { this.inFlight.delete(key); }
  }
  async build(kind, pet, onProgress) {
    if (!this.key) throw new Error('Add the fal.ai API key to the backend before animating pets. No credits were charged.');
    const stages = kind === 'sleep'
      ? ['prepare', 'sleep_pose_video', 'sleep_pose_background', 'sleep_pose_frames', 'sleep_pose_check', 'video', 'background', 'frames', 'verify', 'snore', 'encode', 'save']
      : ['prepare', 'video', 'background', 'frames', 'save'];
    const report = stage => onProgress({ kind, stage, completedStages: stage === 'completed' ? stages.length : stages.indexOf(stage), totalStages: stages.length });
    report('prepare');
    const destination = this.path(pet.id, kind), existing = await this.cached(pet.id, kind);
    if (existing) { report('completed'); return existing; }
    const parent = join(this.directory, pet.id);
    await mkdir(parent, { recursive: true });
    const staging = await mkdtemp(join(parent, '.animation-'));
    try {
      const original = Buffer.from(pet.image, 'base64');
      // Keep the exact cutout. Only the temporary video reference is composited on white.
      await writeFile(join(parent, 'original.png'), original);
      const requestIDs = [], videoPath = join(staging, 'transparent-pet.webm');
      const upload = async reference => this.client.storage.upload(new Blob([await sharp(reference).flatten({ background: '#ffffff' }).png().toBuffer()], { type: 'image/png' }));
      const inspectSleeping = async reference => {
        const imageURL = await upload(reference);
        const result = await this.client.subscribe(POSE_MODEL, { input: {
          image_url: imageURL, prompt: 'Inspect only the animal. Return JSON only: {"pose":"back"|"side"|"upright"|"unknown","eyes_closed":true|false}. Use back only for lying on its back belly up. Use side only for fully reclining on its side. A sitting or standing animal, even with closed eyes, is upright. If unclear use unknown.', reasoning: false, temperature: 0
        }, logs: false, timeout: 120_000 });
        requestIDs.push(result.requestId);
        return parseSleepingPose(result.data.output);
      };
      const render = async (reference, prompt, settling = false) => {
        const imageURL = await upload(reference);
        report(settling ? 'sleep_pose_video' : 'video');
        const generated = await this.client.subscribe(settling ? POSE_VIDEO_MODEL : VIDEO_MODEL, { input: {
          ...(settling ? { image_url: imageURL } : { first_image_url: imageURL, end_image_url: imageURL, aspect_ratio: '1:1' }), prompt, duration: ANIMATIONS[kind], resolution: '720p',
          generate_audio_switch: false, generate_multi_clip_switch: false, thinking_type: 'disabled',
          negative_prompt: 'camera movement, zoom, scene cuts, changing markings, changing proportions, cropped paws, cropped ears, cropped tail, extra limbs, additional animals, text'
        }, logs: false, timeout: 600_000 });
        report(settling ? 'sleep_pose_background' : 'background');
        const matte = await this.client.subscribe(MATTE_MODEL, { input: {
          video_url: generated.data.video.url, output_codec: 'vp9', subject_is_person: false, refine_foreground_edges: true
        }, logs: false, timeout: 600_000 });
        requestIDs.push(generated.requestId, matte.requestId);
        report(settling ? 'sleep_pose_frames' : 'frames');
        await this.download(matte.data.video[0].url, videoPath);
        return this.extract(videoPath, staging, ANIMATIONS[kind]);
      };
      let reference = original;
      if (kind === 'sleep') {
        const seed = join(parent, `sleep-reference-v${SLEEP_REVISION}.png`), marker = seed + '.json';
        const sourceHash = createHash('sha256').update(original).digest('hex');
        try {
          const saved = JSON.parse(await readFile(marker, 'utf8'));
          if (saved.revision !== SLEEP_REVISION || saved.sourceHash !== sourceHash || !['back', 'side'].includes(saved.pose)) throw new Error('Old sleeping seed.');
          reference = await readFile(seed);
        }
        catch {
          // Derive a sleeping start pose from continuous motion, without separately redrawing the pet.
          const settling = await render(original, animationPrompt(kind), true);
          reference = await readFile(join(staging, settling.at(-1)));
          report('sleep_pose_check');
          const pose = await inspectSleeping(reference);
          await writeFile(seed, reference);
          await writeFile(marker, JSON.stringify({ revision: SLEEP_REVISION, sourceHash, pose }));
        }
      }
      const frames = await render(reference, kind === 'sleep' ? sleepLoop : animationPrompt(kind));
      let effects;
      if (kind === 'sleep') {
        report('verify');
        const mouthPoints = [];
        for (const frame of [0, Math.floor(frames.length / 2), frames.length - 1]) {
          const reference = await readFile(join(staging, frames[frame]));
          await inspectSleeping(reference);
          const result = await this.client.subscribe(MOUTH_MODEL, { input: {
            image_url: await upload(reference), prompt: 'the center of the sleeping animal’s mouth', preview: false
          }, logs: false, timeout: 120_000 });
          requestIDs.push(result.requestId);
          mouthPoints.push({ frame, ...parseMouthPoint(result.data.points) });
        }
        report('snore');
        effects = await applySnoreEffects(staging, frames, mouthPoints);
        await validateFrames(staging, ANIMATIONS[kind] * 15);
        // Re-encode the transparent deliverable from the final PNGs so it also contains the visible Zs.
        report('encode');
        await execute(process.env.FFMPEG_PATH ?? 'ffmpeg', ['-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
          '-framerate', '15', '-i', join(staging, 'frame_%04d.png'), '-an', '-c:v', 'libvpx-vp9', '-lossless', '1',
          '-pix_fmt', 'yuva420p', '-auto-alt-ref', '0', videoPath], { timeout: 120_000, maxBuffer: 1_000_000 });
      }
      report('save');
      const manifest = { version: 1, kind, fps: 15, width: 512, height: 512, frameCount: frames.length,
        duration: frames.length / 15, loop: true, referenceEndpoints: 'same', loopSeamVerified: false, canvas: 'fixed', frames,
        providers: { video: VIDEO_MODEL, matte: MATTE_MODEL, ...(kind === 'sleep' ? { poseCheck: POSE_MODEL, mouth: MOUTH_MODEL } : {}) }, requestIDs,
        sleepPosePrepared: kind === 'sleep', ...(kind === 'sleep' ? { behaviorRevision: SLEEP_REVISION, effects } : {}) };
      await writeFile(join(staging, 'animation.json'), JSON.stringify(manifest, null, 2));
      await rm(destination, { recursive: true, force: true });
      await rename(staging, destination);
      report('completed');
      return manifest;
    } catch { throw new Error(failure); }
    finally { await rm(staging, { recursive: true, force: true }); }
  }
}
