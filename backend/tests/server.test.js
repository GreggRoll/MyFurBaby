import test from 'node:test';
import assert from 'node:assert/strict';
import { createBackend } from '../server.js';
import { Ledger, PRODUCTS, addMonths } from '../ledger.js';
const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==';
const recipe = { animal: 'rhino', color: 'purple', accessories: 'monocle', personality: 'goofy' };
async function setup(t, overrides = {}, animations) {
  const ledger = new Ledger(), calls = [];
  const images = { generate: async () => { calls.push('generate'); return { image: png }; }, pose: async kind => { calls.push(kind); return { image: png }; }, photo: async () => { calls.push('photo'); return { image: png }; }, background: async () => { calls.push('background'); return { image: png }; }, ...overrides };
  const { server } = createBackend({ ledger, images, animations });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); ledger.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = async (path, token, method = 'GET', data, key) => {
    const response = await fetch(base + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(key ? { 'Idempotency-Key': key } : {}) }, body: data ? JSON.stringify(data) : undefined });
    return { status: response.status, body: await response.json() };
  };
  const session = (await request('/v1/session', null, 'POST', {})).body;
  return { ledger, calls, request, session };
}
test('HTTP generation, same-key retry and recovery debit once; jobs stay private', async t => {
  const { request, session, calls } = await setup(t);
  const payload = { kind: 'pet', recipe, name: '' }, key = '550e8400-e29b-41d4-a716-446655440000';
  assert.equal((await request('/v1/wallet')).status, 401);
  const first = await request('/v1/jobs', session.token, 'POST', payload, key);
  const retry = await request('/v1/jobs', session.token, 'POST', payload, key);
  assert.equal(first.status, 202); assert.equal(first.body.id, retry.body.id); assert.equal(calls.length, 1);
  const job = await request('/v1/jobs/' + first.body.id, session.token);
  assert.equal(job.body.status, 'completed'); assert.equal(job.body.result.imageBase64, png); assert.equal(job.body.result.wallet.trialCredits, 0);
  const recovered = await request('/v1/jobs/by-key/' + key, session.token); assert.equal(recovered.body.id, first.body.id);
  const stranger = (await request('/v1/session', null, 'POST', {})).body;
  assert.equal((await request('/v1/jobs/' + first.body.id, stranger.token)).status, 404);
  assert.equal((await request('/v1/jobs/by-key/' + key, stranger.token)).status, 404);
});

test('video jobs share pending requests, cache completed frames, and remain private', async t => {
  let release; let calls = 0;
  const manifest = { kind: 'run', fps: 15, width: 512, height: 512, frames: ['frame_0001.png'], frameCount: 1, duration: 1 / 15 };
  const animations = {
    cached: async () => calls ? manifest : null,
    generate: async (kind, pet, onProgress) => {
      calls++;
      onProgress({ kind, stage: 'background', completedStages: 2, totalStages: 5 });
      await new Promise(resolve => { release = resolve; });
      onProgress({ kind, stage: 'completed', completedStages: 5, totalStages: 5 });
      return manifest;
    },
    response: async (_, value) => ({ ...value, framesBase64: [png] })
  };
  const { ledger, session, request } = await setup(t, {}, animations);
  const petID = ledger.savePet(session.accountID, recipe, png), path = `/v1/pets/${petID}/animations`;
  assert.equal((await request(path, session.token, 'POST', { kind: 'run' })).status, 400);
  ledger.purchase(session.accountID, { transactionId: 'video-pro', productId: PRODUCTS.monthly, expiresDate: addMonths(Date.now(), 1), appAccountToken: session.accountID });
  assert.equal((await request(path, session.token, 'POST', { kind: 'invalid' })).status, 400);
  const first = await request(path, session.token, 'POST', { kind: 'run' });
  const retry = await request(path, session.token, 'POST', { kind: 'run' });
  assert.equal(first.status, 202); assert.equal(first.body.id, retry.body.id); assert.equal(calls, 1);
  const pending = await request('/v1/jobs/' + first.body.id, session.token);
  assert.equal(pending.body.status, 'pending');
  assert.deepEqual(pending.body.progress, { kind: 'run', stage: 'background', completedStages: 2, totalStages: 5 });
  release();
  const completed = await request('/v1/jobs/' + first.body.id, session.token);
  assert.equal(completed.body.progress.stage, 'completed');
  assert.equal(completed.body.result.animation.framesBase64[0], png);
  const cached = await request(path, session.token, 'POST', { kind: 'run' });
  assert.equal(cached.body.id, first.body.id); assert.equal(calls, 1);
  assert.equal(ledger.wallet(session.accountID).subscriptionCredits, 3500);
  const stranger = (await request('/v1/session', null, 'POST', {})).body;
  assert.equal((await request('/v1/jobs/' + first.body.id, stranger.token)).status, 404);
});

test('failed video jobs refund, redact provider errors and retry only once', async t => {
  let fail = true, calls = 0;
  const animations = { cached: async () => null, response: async (_, value) => value,
    generate: async kind => { calls++; if (fail) throw new Error('secret-provider-error'); return { kind }; } };
  const { ledger, session, request } = await setup(t, {}, animations);
  ledger.purchase(session.accountID, { transactionId: 'failed-video-pro', productId: PRODUCTS.monthly, expiresDate: addMonths(Date.now(), 1), appAccountToken: session.accountID });
  const petID = ledger.savePet(session.accountID, recipe, png), path = `/v1/pets/${petID}/animations`;
  const first = await request(path, session.token, 'POST', { kind: 'sleep' });
  const failed = await request('/v1/jobs/' + first.body.id, session.token);
  assert.equal(failed.body.status, 'failed'); assert.doesNotMatch(failed.body.error, /secret/);
  assert.equal(ledger.wallet(session.accountID).subscriptionCredits, 5000);
  fail = false;
  const retry = await request(path, session.token, 'POST', { kind: 'sleep' });
  assert.notEqual(first.body.id, retry.body.id); assert.equal(calls, 2);
  assert.equal(ledger.wallet(session.accountID).subscriptionCredits, 3500);
});
test('HTTP failed provider job returns credits and sanitized failure', async t => {
  const { request, session } = await setup(t, { generate: async () => { throw new Error('Generation failed. Reserved credits were returned.'); } });
  const receipt = await request('/v1/jobs', session.token, 'POST', { kind: 'pet', recipe }, 'failing-request');
  const job = await request('/v1/jobs/' + receipt.body.id, session.token);
  assert.equal(job.body.status, 'failed'); assert.equal((await request('/v1/wallet', session.token)).body.trialCredits, 250);
});
test('invalid descriptions and non-Pro photo edits cannot spend credits', async t => {
  const { request, session, ledger } = await setup(t);
  assert.equal((await request('/v1/jobs', session.token, 'POST', { kind: 'pet', recipe: { ...recipe, color: '' } }, 'invalid-description')).status, 400);
  const petID = ledger.savePet(session.accountID, recipe, png);
  assert.equal((await request('/v1/jobs', session.token, 'POST', { kind: 'photo', recipe, petID, photoBase64: png, placement: 'beside me' }, 'locked-photo')).status, 400);
  assert.equal((await request('/v1/wallet', session.token)).body.trialCredits, 250);
  assert.equal((await request('/v1/purchases', session.token, 'POST', { signedTransaction: 'fake' })).status, 503);
});
test('two animation sheets cost 3000 once; cached replay costs nothing', async t => {
  const { request, session, ledger, calls } = await setup(t);
  ledger.purchase(session.accountID, { transactionId: 'pro-test', productId: PRODUCTS.monthly, purchaseDate: Date.now(), expiresDate: addMonths(Date.now(), 1), appAccountToken: session.accountID });
  const petID = ledger.savePet(session.accountID, recipe, png), path = `/v1/pets/${petID}/poses`;
  const first = await request(path, session.token, 'POST', {}); assert.equal(first.status, 200); assert.equal(first.body.wallet.subscriptionCredits, 2000);
  const again = await request(path, session.token, 'POST', {}); assert.equal(again.body.wallet.subscriptionCredits, 2000); assert.deepEqual(calls, ['sleep', 'playful']);
});
test('partial animation failure refunds the failed sheet and retries only missing sheet', async t => {
  let shouldFail = true;
  const { request, session, ledger } = await setup(t, { pose: async kind => { if (kind === 'playful' && shouldFail) throw new Error('Try again.'); return { image: png }; } });
  ledger.purchase(session.accountID, { transactionId: 'pro-test', productId: PRODUCTS.monthly, purchaseDate: Date.now(), expiresDate: addMonths(Date.now(), 1), appAccountToken: session.accountID });
  const petID = ledger.savePet(session.accountID, recipe, png), path = `/v1/pets/${petID}/poses`;
  assert.equal((await request(path, session.token, 'POST', {})).status, 400);
  assert.equal((await request('/v1/wallet', session.token)).body.subscriptionCredits, 3500);
  shouldFail = false; assert.equal((await request(path, session.token, 'POST', {})).body.wallet.subscriptionCredits, 2000);
});

test('onboarding creates one free pet, preserves gender, and never spends purchased credits', async t => {
  let captured;
  const { request, session, ledger } = await setup(t, { generate: async value => { captured = value; return { image: png }; } });
  ledger.purchase(session.accountID, { transactionId: 'onboarding-pack', productId: PRODUCTS.pack, appAccountToken: session.accountID });
  const payload = { kind: 'pet', onboarding: true, recipe: { ...recipe, gender: 'girl' } };
  const first = await request('/v1/jobs', session.token, 'POST', payload, 'onboarding-free-pet');
  assert.equal(first.status, 202);
  assert.equal(captured.gender, 'girl');
  const job = await request('/v1/jobs/' + first.body.id, session.token);
  assert.equal(job.body.result.wallet.trialCredits, 0);
  assert.equal(job.body.result.wallet.purchasedCredits, 5000);
  const again = await request('/v1/jobs', session.token, 'POST', payload, 'onboarding-free-pet');
  assert.equal(again.body.id, first.body.id);
  assert.equal((await request('/v1/jobs', session.token, 'POST', payload, 'onboarding-second-pet')).status, 400);
  assert.equal((await request('/v1/wallet', session.token)).body.purchasedCredits, 5000);
});

test('failed free onboarding can retry without payment; invalid gender cannot spend allowance', async t => {
  let fail = true;
  const { request, session } = await setup(t, { generate: async () => { if (fail) throw new Error('Try again.'); return { image: png }; } });
  const payload = { kind: 'pet', onboarding: true, recipe: { ...recipe, gender: 'boy' } };
  assert.equal((await request('/v1/jobs', session.token, 'POST', { ...payload, recipe: { ...recipe, gender: 'invalid' } }, 'invalid-gender')).status, 400);
  assert.equal((await request('/v1/wallet', session.token)).body.trialCredits, 250);
  const first = await request('/v1/jobs', session.token, 'POST', payload, 'onboarding-failure');
  assert.equal((await request('/v1/jobs/' + first.body.id, session.token)).body.status, 'failed');
  assert.equal((await request('/v1/wallet', session.token)).body.trialCredits, 250);
  fail = false;
  const retry = await request('/v1/jobs', session.token, 'POST', payload, 'onboarding-retry');
  assert.equal((await request('/v1/jobs/' + retry.body.id, session.token)).body.status, 'completed');
});


test('custom backgrounds cost 200 once, remain private, and do not create a pet', async t => {
  const { request, session, ledger, calls } = await setup(t);
  const payload = { kind: 'background', prompt: 'A cozy moonlit treehouse', price: 1 };
  const path = '/v1/jobs', key = '550e8400-e29b-41d4-a716-446655440009';
  assert.equal((await request(path, session.token, 'POST', payload, key)).status, 400);
  assert.equal(ledger.wallet(session.accountID).trialCredits, 250);
  ledger.purchase(session.accountID, { transactionId: 'background-pro', productId: PRODUCTS.monthly, expiresDate: addMonths(Date.now(), 1), appAccountToken: session.accountID });
  for (const prompt of ['', '   ', 'a'.repeat(501)]) {
    assert.equal((await request(path, session.token, 'POST', { kind: 'background', prompt }, key)).status, 400);
  }
  const first = await request(path, session.token, 'POST', payload, key);
  const retry = await request(path, session.token, 'POST', payload, key);
  assert.equal(first.status, 202); assert.equal(retry.body.id, first.body.id);
  const job = await request('/v1/jobs/' + first.body.id, session.token);
  assert.equal(job.body.result.imageBase64, png);
  assert.equal(job.body.result.petID, null);
  assert.equal(job.body.result.wallet.subscriptionCredits, 4800);
  assert.deepEqual(calls, ['background']);
  assert.equal(ledger.db.prepare('SELECT COUNT(*) AS count FROM pets').get().count, 0);
  assert.equal((await request('/v1/jobs/by-key/' + key, session.token)).body.id, first.body.id);
  assert.equal((await request(path, session.token, 'POST', { ...payload, prompt: 'Different scene' }, key)).status, 400);
  const stranger = (await request('/v1/session', null, 'POST', {})).body;
  assert.equal((await request('/v1/jobs/' + first.body.id, stranger.token)).status, 404);
});

test('failed backgrounds refund their split debit, while insufficient tokens never call the provider', async t => {
  const { request, session, ledger, calls } = await setup(t, { background: async () => { calls.push('background'); throw new Error('secret-provider-body'); } });
  ledger.purchase(session.accountID, { transactionId: 'background-refund-pro', productId: PRODUCTS.monthly, expiresDate: addMonths(Date.now(), 1), appAccountToken: session.accountID });
  ledger.db.prepare('UPDATE users SET sub_credits=100,pack_credits=100 WHERE id=?').run(session.accountID);
  const payload = { kind: 'background', prompt: 'Cloud castle' };
  const first = await request('/v1/jobs', session.token, 'POST', payload, 'background-refund');
  const failed = await request('/v1/jobs/' + first.body.id, session.token);
  assert.equal(failed.body.status, 'failed'); assert.doesNotMatch(failed.body.error, /secret/);
  assert.equal(ledger.wallet(session.accountID).subscriptionCredits, 100);
  assert.equal(ledger.wallet(session.accountID).purchasedCredits, 100);
  ledger.db.prepare('UPDATE users SET pack_credits=99 WHERE id=?').run(session.accountID);
  const rejected = await request('/v1/jobs', session.token, 'POST', payload, 'background-too-few');
  assert.equal(rejected.status, 400); assert.match(rejected.body.error, /200 credits/);
  assert.deepEqual(calls, ['background']);
});

test('animations enforce 1500 tokens before starting provider work', async t => {
  let calls = 0;
  const animations = { cached: async () => null, generate: async () => { calls++; return {}; } };
  const { request, session, ledger } = await setup(t, {}, animations);
  ledger.purchase(session.accountID, { transactionId: 'animation-too-few-pro', productId: PRODUCTS.monthly, expiresDate: addMonths(Date.now(), 1), appAccountToken: session.accountID });
  ledger.db.prepare('UPDATE users SET sub_credits=1499 WHERE id=?').run(session.accountID);
  const petID = ledger.savePet(session.accountID, recipe, png);
  const rejected = await request(`/v1/pets/${petID}/animations`, session.token, 'POST', { kind: 'playful', price: 1 });
  assert.equal(rejected.status, 400); assert.match(rejected.body.error, /1500 credits/);
  assert.equal(calls, 0); assert.equal(ledger.wallet(session.accountID).subscriptionCredits, 1499);
});


test('idle animation route charges once and recovers its completed job for free', async t => {
  let calls = 0, ready = false;
  const output = { kind: 'idle', fps: 15, frameCount: 30, duration: 2, frames: [] };
  const animations = { cached: async (_, kind) => ready && kind === 'idle' ? output : null,
    generate: async (_, pet, progress) => {
      calls++; progress({ kind: 'idle', stage: 'completed', completedStages: 5, totalStages: 5 });
      ready = true; return output;
    }, response: async (_, result) => ({ ...result, framesBase64: [] }) };
  const { request, session, ledger } = await setup(t, {}, animations);
  ledger.purchase(session.accountID, { transactionId: 'idle-pro', productId: PRODUCTS.monthly,
    expiresDate: addMonths(Date.now(), 1), appAccountToken: session.accountID });
  ledger.db.prepare('UPDATE users SET sub_credits=1500 WHERE id=?').run(session.accountID);
  const petID = ledger.savePet(session.accountID, recipe, png);
  const first = await request(`/v1/pets/${petID}/animations`, session.token, 'POST', { kind: 'idle' });
  assert.equal(first.status, 202);
  const job = await request('/v1/jobs/' + first.body.id, session.token);
  assert.equal(job.body.status, 'completed'); assert.equal(job.body.result.animation.kind, 'idle');
  assert.equal(ledger.wallet(session.accountID).subscriptionCredits, 0);
  const replay = await request(`/v1/pets/${petID}/animations`, session.token, 'POST', { kind: 'idle' });
  assert.equal(replay.body.id, first.body.id); assert.equal(calls, 1);
});

test('playful request reuses the legacy paid job and does not reserve credits again', async t => {
  let calls = 0;
  const animations = { cached: async (_, kind) => kind === 'playful' ? { kind } : null,
    generate: async () => { calls++; throw new Error('Must reuse existing job'); },
    response: async (_, result) => ({ ...result, framesBase64: [] }) };
  const { request, session, ledger } = await setup(t, {}, animations);
  ledger.purchase(session.accountID, { transactionId: 'legacy-playful-pro', productId: PRODUCTS.monthly,
    expiresDate: addMonths(Date.now(), 1), appAccountToken: session.accountID });
  const petID = ledger.savePet(session.accountID, recipe, png);
  const { job } = ledger.reserve(session.accountID, `animation-${petID}-lick-0`, 'old-hash', true, false, 1500);
  ledger.complete(job.id, { petID, animation: { kind: 'lick', fps: 15, frameCount: 45 } });
  const before = ledger.wallet(session.accountID);
  const replay = await request(`/v1/pets/${petID}/animations`, session.token, 'POST', { kind: 'playful' });
  assert.equal(replay.status, 202); assert.equal(replay.body.id, job.id);
  assert.deepEqual(ledger.wallet(session.accountID), before); assert.equal(calls, 0);
  const oldClient = await request(`/v1/pets/${petID}/animations`, session.token, 'POST', { kind: 'lick' });
  assert.equal(oldClient.body.id, job.id); assert.deepEqual(ledger.wallet(session.accountID), before);
});
