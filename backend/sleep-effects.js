import sharp from 'sharp';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

export const SLEEP_REVISION = 2;
export const POSE_MODEL = 'fal-ai/moondream3-preview/query';
export const MOUTH_MODEL = 'fal-ai/moondream3-preview/point';

export function parseSleepingPose(output) {
  if (typeof output !== 'string') throw new Error('Sleeping pose could not be checked.');
  const value = JSON.parse(output.replace(/^\s*```(?:json)?\s*/i, '').replace(/\s*```\s*$/, ''));
  // The live vision model also returns descriptions, e.g. "lying on its back belly up".
  // Normalize only unambiguous reclining phrases; substring matching could accept "not lying".
  const description = typeof value?.pose === 'string'
    ? value.pose.trim().toLowerCase().replace(/[.,!;:]/g, '').replace(/\s+/g, ' ') : '';
  const back = ['back', 'on its back', 'lying on its back', 'lying on its back belly up',
    'lying on its back with belly up', 'lying on its back with its belly up', 'supine'];
  const side = ['side', 'on its side', 'lying on its side', 'fully reclining on its side',
    'reclining on its side', 'fully reclined on its side'];
  const pose = back.includes(description) ? 'back' : side.includes(description) ? 'side' : null;
  if (!pose || value.eyes_closed !== true || value.unknown === true) {
    throw new Error('The animal must be asleep on its back or side.');
  }
  return pose;
}

export function parseMouthPoint(points) {
  if (!Array.isArray(points) || points.length !== 1) throw new Error('The sleeping animal’s mouth could not be located.');
  const { x, y } = points[0];
  if (!Number.isFinite(x) || !Number.isFinite(y) || x <= 0 || x >= 1 || y <= 0 || y >= 1) throw new Error('Invalid mouth position.');
  return { x, y };
}

function mouthAt(frame, points) {
  const next = points.findIndex(point => point.frame >= frame);
  if (next <= 0) return points[next === 0 ? 0 : points.length - 1];
  const a = points[next - 1], b = points[next], t = (frame - a.frame) / (b.frame - a.frame);
  return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
}

export function snoreOverlaySVG(frame, fps, mouth, width = 512, height = 512) {
  parseMouthPoint([mouth]);
  // Vector Zs avoid provider spelling errors and dependencies on system fonts.
  // Every letter is emitted at the mouth, floats outward/upward, grows and fades in a two-second cycle.
  const cycle = 2, direction = mouth.x <= 0.5 ? 1 : -1, letters = [];
  for (let letter = 0; letter < 3; letter++) {
    const phase = ((frame / fps / cycle + letter / 3) % 1 + 1) % 1;
    const opacity = Math.min(1, phase / 0.12, (1 - phase) / 0.25);
    const scale = (0.7 + phase * 0.75) * width / 512;
    const rise = Math.min(height * 0.24, Math.max(0, mouth.y * height - 40));
    const x = Math.max(4, Math.min(width - 32 * scale - 4, mouth.x * width + direction * phase * width * 0.12));
    const y = Math.max(4, Math.min(height - 32 * scale - 4, mouth.y * height - phase * rise));
    letters.push(`<path d="M0 0H18V4L5 18H18V22H0V18L13 4H0Z" transform="translate(${x.toFixed(2)} ${y.toFixed(2)}) scale(${scale.toFixed(4)})" opacity="${opacity.toFixed(4)}" fill="#784694" stroke="#ffffff" stroke-width="1.5" stroke-linejoin="round"/>`);
  }
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${letters.join('')}</svg>`);
}

export async function applySnoreEffects(directory, frames, mouthPoints, { fps = 15, width = 512, height = 512 } = {}) {
  if (!Array.isArray(mouthPoints) || mouthPoints.length < 2 || mouthPoints[0].frame !== 0 || mouthPoints.at(-1).frame !== frames.length - 1) throw new Error('Mouth tracking is incomplete.');
  for (const [index, point] of mouthPoints.entries()) {
    parseMouthPoint([point]);
    if (!Number.isInteger(point.frame) || (index && point.frame <= mouthPoints[index - 1].frame)) throw new Error('Invalid mouth tracking.');
  }
  for (const [index, file] of frames.entries()) {
    if (!/^frame_\d{4}\.png$/.test(file)) throw new Error('Invalid animation frame.');
    const path = join(directory, file), original = await readFile(path);
    const image = sharp(original), metadata = await image.metadata();
    if (metadata.width !== width || metadata.height !== height || !metadata.hasAlpha) throw new Error('Invalid animation canvas.');
    const png = await image.composite([{ input: snoreOverlaySVG(index, fps, mouthAt(index, mouthPoints), width, height) }]).png().toBuffer();
    await writeFile(path, png);
  }
  return { type: 'floating-zs', text: 'Zzz', cycleSeconds: 2, origin: 'tracked-mouth', mouthPoints };
}
