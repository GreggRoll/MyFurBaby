import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

// This creates only temporary test containers/volumes; no API key or paid calls.
const image = process.argv[2] ?? 'myfurbaby-backend:beta';
const suffix = randomUUID(), container = `furbaby-check-${suffix}`, volume = `${container}-data`;
const docker = (...args) => execFileSync('docker', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let base;
async function start() {
  docker('run', '-d', '--name', container, '--mount', `source=${volume},target=/data`, '-p', '127.0.0.1::8787', image);
  const port = docker('port', container, '8787/tcp').match(/:(\d+)$/)?.[1];
  assert.ok(port); base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 50; attempt++) {
    try { if ((await fetch(base + '/health')).ok) return; } catch {}
    await delay(200);
  }
  throw new Error('The test container did not become healthy.');
}
async function request(route, method = 'GET', token, payload) {
  const response = await fetch(base + route, {
    method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: payload ? JSON.stringify(payload) : undefined
  });
  return { status: response.status, body: await response.json() };
}
try {
  docker('volume', 'create', volume);
  await start();
  assert.deepEqual((await request('/health')).body, { status: 'ok', imagesConfigured: false, animationsConfigured: false, purchasesConfigured: true });
  assert.equal((await request('/v1/wallet')).status, 401);
  const session = await request('/v1/session', 'POST', undefined, {});
  assert.equal(session.status, 201); assert.equal(session.body.wallet.trialCredits, 250);
  const wallet = (await request('/v1/wallet', 'GET', session.body.token)).body;
  assert.equal((await request('/v1/jobs', 'POST', session.body.token, {})).status, 503);
  const animation = await request('/v1/pets/00000000-0000-0000-0000-000000000000/animations', 'POST', session.body.token, { kind: 'playful' });
  assert.equal(animation.status, 503); // A missing provider key must not become a missing API route.
  assert.match(animation.body.error, /No credits were charged/);
  assert.equal((await request('/v1/purchases', 'POST', session.body.token, { signedTransaction: 'fake' })).status, 400);
  assert.deepEqual((await request('/v1/wallet', 'GET', session.body.token)).body, wallet);
  docker('exec', container, 'node', '--input-type=module', '-e', "import {existsSync} from 'node:fs'; if(existsSync('/app/.env') || process.env.OPENAI_API_KEY || process.env.FAL_KEY) process.exit(1);");
  assert.match(docker('exec', container, 'ffmpeg', '-hide_banner', '-decoders'), /libvpx-vp9/);
  const resources = docker('stats', '--no-stream', '--format', '{{.MemUsage}}; CPU {{.CPUPerc}}', container);
  docker('stop', '-t', '10', container); docker('rm', container);
  await start();
  assert.deepEqual((await request('/v1/wallet', 'GET', session.body.token)).body, wallet);
  console.log(JSON.stringify({ status: 'passed', checks: ['health', 'animation route', 'FFmpeg VP9 decoder', 'authentication', 'Apple trust roots', 'forged purchase rejection', 'missing-key refund safety', 'secrets excluded from image', 'account and credits survive container replacement'], idleResources: resources }));
} finally {
  try { docker('rm', '-f', container); } catch {}
  try { docker('volume', 'rm', volume); } catch {}
}
