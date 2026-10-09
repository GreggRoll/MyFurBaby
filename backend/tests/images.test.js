import test from 'node:test';
import assert from 'node:assert/strict';
import { OpenAIImages, decodeImage } from '../openai.js';
import { validateRecipe } from '../prompts.js';
import sharp from 'sharp';
const png = (await sharp({ create: { width: 4, height: 4, channels: 4, background: '#800080' } }).png().toBuffer()).toString('base64');
const recipe = { animal: 'gigglegoop', color: 'yellow ombré', accessories: 'top hat and monocle', personality: 'sassy' };
function mock() {
  const requests = [];
  return { requests, images: new OpenAIImages('fake-test-key', async (url, options) => { requests.push({ url, ...options }); return new Response(JSON.stringify({ data: [{ b64_json: png }], usage: { output_tokens: 42 } }), { headers: { 'x-request-id': 'test' } }); }) };
}
test('free-text imaginary animals are accepted; blanks and long fields are rejected', () => {
  assert.deepEqual(validateRecipe(recipe), recipe);
  assert.throws(() => validateRecipe({ ...recipe, animal: '  ' }));
  assert.throws(() => validateRecipe({ ...recipe, personality: 'a'.repeat(301) }));
  assert.equal(validateRecipe({ ...recipe, accessories: '' }).accessories, '');
});
test('creation uses supported GPT Image 2 opaque output before background removal', async () => {
  const { images, requests } = mock(); const output = await images.generate(recipe);
  const request = requests[0], payload = JSON.parse(request.body);
  assert.equal(request.url, 'https://api.openai.com/v1/images/generations');
  assert.equal(payload.model, 'gpt-image-2'); assert.equal(payload.quality, 'medium'); assert.equal(payload.background, 'opaque');
  assert.match(payload.prompt, /gigglegoop/); assert.match(payload.prompt, /pure white/); assert.equal(decodeImage(output.image).type, 'image/png');
});
test('boy and girl recipes reach the image provider prompt with their appearance choices', async () => {
  for (const gender of ['boy', 'girl']) {
    const { images, requests } = mock();
    await images.generate(validateRecipe({ ...recipe, gender }));
    const prompt = JSON.parse(requests[0].body).prompt;
    assert.ok(prompt.includes(JSON.stringify({ ...recipe, gender })));
    assert.match(prompt, /requested boy or girl animal/);
  }
});
test('photo edits include source photo and exact pet reference in that order', async () => {
  const { images, requests } = mock(); await images.photo(png, { recipe: JSON.stringify(recipe), image: png }, 'On my lap');
  const { body, url, headers } = requests[0];
  assert.equal(url, 'https://api.openai.com/v1/images/edits'); assert.equal(body.get('model'), 'gpt-image-2');
  assert.equal(body.getAll('image[]').length, 2); assert.equal(body.get('background'), 'opaque');
  assert.match(body.get('prompt'), /On my lap/); assert.equal(headers['Content-Type'], undefined);
});
test('widget backgrounds keep their opaque scenery instead of removing the image background', async () => {
  const { images, requests } = mock();
  const output = await images.background('A moonlit garden');
  const payload = JSON.parse(requests[0].body);
  assert.equal(output.image, png);
  assert.equal(payload.background, 'opaque');
  assert.match(payload.prompt, /moonlit garden/);
  assert.match(payload.prompt, /No animals/);
  assert.match(payload.prompt, /right side/);
});
test('provider secrets and error bodies never reach the user', async () => {
  const images = new OpenAIImages('fake-test-key', async () => new Response(JSON.stringify({ error: { message: 'sensitive-provider-data' } }), { status: 500 }));
  await assert.rejects(images.generate(recipe), error => !error.message.includes('sensitive') && error.message.includes('returned'));
  await assert.rejects(new OpenAIImages().generate(recipe), /not configured/);
  assert.throws(() => decodeImage(Buffer.from('not an image').toString('base64')));
});
