import sharp from 'sharp';

// GPT Image 2 rejects transparent output for this project. Request an empty pure-white
// background, then remove white connected to the image border. Interior whites stay intact.
// This is a deterministic matte, not semantic segmentation; pale edge quality needs review.
export async function cutoutWhiteBorder(base64) {
  const { data, info } = await sharp(Buffer.from(base64, 'base64'), { limitInputPixels: 16_777_216 }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info, count = width * height;
  const visited = new Uint8Array(count), queue = new Uint32Array(count);
  let head = 0, tail = 0;
  function push(index) {
    if (visited[index]) return;
    visited[index] = 1;
    const offset = index * channels;
    if (data[offset] >= 245 && data[offset + 1] >= 245 && data[offset + 2] >= 245) queue[tail++] = index;
  }
  for (let x = 0; x < width; x++) { push(x); push((height - 1) * width + x); }
  for (let y = 0; y < height; y++) { push(y * width); push(y * width + width - 1); }
  while (head < tail) {
    const index = queue[head++], x = index % width, y = Math.floor(index / width);
    data[index * channels + 3] = 0;
    if (x > 0) push(index - 1); if (x + 1 < width) push(index + 1);
    if (y > 0) push(index - width); if (y + 1 < height) push(index + width);
  }
  return (await sharp(data, { raw: { width, height, channels } }).png().toBuffer()).toString('base64');
}
