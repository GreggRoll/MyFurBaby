import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { cutoutWhiteBorder } from '../cutout.js';

test('cutout removes only border-connected white and preserves enclosed white details', async () => {
  const width = 9, bytes = Buffer.alloc(width * width * 4, 255);
  for (let y = 2; y <= 6; y++) for (let x = 2; x <= 6; x++) {
    const offset = (y * width + x) * 4; bytes[offset] = 140; bytes[offset + 1] = 75; bytes[offset + 2] = 200;
  }
  const eye = (4 * width + 4) * 4; bytes[eye] = bytes[eye + 1] = bytes[eye + 2] = 255;
  const image = await sharp(bytes, { raw: { width, height: width, channels: 4 } }).png().toBuffer();
  const output = await cutoutWhiteBorder(image.toString('base64'));
  const raw = await sharp(Buffer.from(output, 'base64')).ensureAlpha().raw().toBuffer();
  assert.equal(raw[3], 0); assert.equal(raw[eye + 3], 255); assert.equal(raw[(2 * width + 2) * 4 + 3], 255);
});
