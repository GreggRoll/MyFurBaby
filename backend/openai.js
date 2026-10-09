import { petPrompt, photoPrompt, backgroundPrompt } from './prompts.js';
import { cutoutWhiteBorder } from './cutout.js';

export function decodeImage(value) {
  if (typeof value !== 'string' || value.length > 17_000_000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw new Error('Choose a valid PNG, JPEG, or WebP image under 12 MB.');
  const bytes = Buffer.from(value, 'base64');
  const png = bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const jpg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  const webp = bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP';
  if (bytes.length > 12_000_000 || (!png && !jpg && !webp)) throw new Error('Choose a valid PNG, JPEG, or WebP image under 12 MB.');
  return { bytes, type: png ? 'image/png' : jpg ? 'image/jpeg' : 'image/webp' };
}

export class OpenAIImages {
  constructor(key, fetcher = fetch) { this.key = key; this.fetch = fetcher; }
  async call(prompt, images = [], transparent = true) {
    if (!this.key) throw new Error('The image service is not configured.');
    const parameters = { model: 'gpt-image-2', prompt, n: 1, quality: 'medium', size: '1024x1024', output_format: 'png', background: 'opaque' };
    let body, headers = { Authorization: `Bearer ${this.key}` };
    if (images.length) {
      body = new FormData();
      for (const [key, value] of Object.entries(parameters)) body.set(key, String(value));
      images.forEach((image, index) => { const decoded = decodeImage(image); body.append('image[]', new Blob([decoded.bytes], { type: decoded.type }), `reference-${index}.${decoded.type.split('/')[1]}`); });
    } else { body = JSON.stringify(parameters); headers['Content-Type'] = 'application/json'; }
    const response = await this.fetch(`https://api.openai.com/v1/images/${images.length ? 'edits' : 'generations'}`, { method: 'POST', headers, body, signal: AbortSignal.timeout(240_000) });
    const result = await response.json();
    if (!response.ok) {
      if (result.error?.code === 'moderation_blocked') throw new Error('Please adjust your description or photo and try again. Credits were returned.');
      throw new Error('Image generation could not finish. Reserved credits were returned.');
    }
    const image = result.data?.[0]?.b64_json;
    decodeImage(image);
    return { image: transparent ? await cutoutWhiteBorder(image) : image, usage: result.usage, requestID: response.headers.get('x-request-id') };
  }
  generate(recipe) { return this.call(petPrompt(recipe)); }
  background(description) { return this.call(backgroundPrompt(description), [], false); }
  photo(photo, pet, placement) { return this.call(photoPrompt(placement, JSON.parse(pet.recipe)), [photo, pet.image], false); }
}
