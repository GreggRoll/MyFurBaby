import { createServer } from 'node:http';
import { readFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { SignedDataVerifier, Environment } from '@apple/app-store-server-library';
import { Ledger, hash, BACKGROUND_PRICE, ANIMATION_PRICE } from './ledger.js';
import { OpenAIImages, decodeImage } from './openai.js';
import { validateRecipe, validateBackground } from './prompts.js';
import { clientIP } from './client-ip.js';
import { FalAnimations, ANIMATIONS, animationKind } from './animations.js';

export function createBackend(options = {}) {
const dataDirectory = resolve(process.env.DATA_DIRECTORY ?? 'data');
if (!options.ledger) mkdirSync(dataDirectory, { recursive: true });
const ledger = options.ledger ?? new Ledger(resolve(dataDirectory, 'myfurbaby.sqlite')); ledger.recoverInterrupted();
const images = options.images ?? new OpenAIImages(process.env.OPENAI_API_KEY);
const imagesConfigured = !!options.images || !!process.env.OPENAI_API_KEY;
const animations = options.animations ?? new FalAnimations(process.env.FAL_KEY, resolve(dataDirectory, 'animations'));
const animationsConfigured = !!options.animations || !!process.env.FAL_KEY;
const roots = (process.env.APPLE_ROOT_CA_PATHS ?? '').split(',').filter(Boolean).map(path => readFileSync(path.trim()));
const appleEnvironment = process.env.APPLE_ENVIRONMENT === 'Production' ? Environment.PRODUCTION : Environment.SANDBOX;
const verifier = roots.length ? new SignedDataVerifier(roots, true, appleEnvironment, process.env.APPLE_BUNDLE_ID ?? 'com.gregadams.myfurbaby', process.env.APPLE_APP_ID ? Number(process.env.APPLE_APP_ID) : undefined) : null;
const poseJobs = new Map(), buckets = new Map();
const trustRailwayProxy = process.env.TRUST_RAILWAY_PROXY === 'true';

function send(response, status, object) { response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); response.end(JSON.stringify(object)); }
async function body(request) {
  let size = 0; const chunks = [];
  for await (const chunk of request) { size += chunk.length; if (size > 18_000_000) throw new Error('This upload is too large.'); chunks.push(chunk); }
  try { return JSON.parse(Buffer.concat(chunks).toString() || '{}'); } catch { throw new Error('The request could not be read.'); }
}
function rateLimit(key, limit, window = 60_000) {
  const now = Date.now(); let bucket = buckets.get(key);
  if (!bucket || bucket.start + window < now) { bucket = { start: now, count: 0 }; buckets.set(key, bucket); }
  bucket.count++; if (bucket.count > limit) throw new Error('Please wait a moment before trying again.');
  if (buckets.size > 10_000) for (const [id, item] of buckets) if (item.start + window < now) buckets.delete(id);
}

const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, 'http://localhost').pathname;
    if (path === '/health') return send(response, 200, { status: 'ok', imagesConfigured, animationsConfigured, purchasesConfigured: !!verifier });
    if (path === '/v1/session' && request.method === 'POST') { rateLimit('session:' + clientIP(request, trustRailwayProxy), 5, 3_600_000); await body(request); return send(response, 201, ledger.createSession()); }
    if (path === '/v1/apple/notifications' && request.method === 'POST') {
      if (!verifier) return send(response, 503, { error: 'Purchase verification is not configured.' });
      const notification = await verifier.verifyAndDecodeNotification((await body(request)).signedPayload);
      if (notification.data?.signedTransactionInfo) {
        const tx = await verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo);
        if (tx.revocationDate || ['REFUND', 'REVOKE'].includes(notification.notificationType)) ledger.revoke(tx);
        else if (tx.appAccountToken && tx.expiresDate > Date.now()) ledger.purchase(tx.appAccountToken, tx);
      }
      return send(response, 200, { received: true });
    }
    const token = request.headers.authorization?.replace(/^Bearer /, ''), userID = token && ledger.authenticate(token);
    if (!userID) return send(response, 401, { error: 'Please reconnect to your Fur Baby account.' });
    rateLimit(userID, 90);
    if (path === '/v1/wallet' && request.method === 'GET') return send(response, 200, ledger.wallet(userID));
    if (path === '/v1/purchases' && request.method === 'POST') {
      if (!verifier) return send(response, 503, { error: 'Configure Apple purchase verification before activating a purchase.' });
      const payload = await body(request);
      const tx = await verifier.verifyAndDecodeTransaction(payload.signedTransaction);
      return send(response, 200, ledger.purchase(userID, tx));
    }
    if (path === '/v1/jobs' && request.method === 'POST') {
      if (!imagesConfigured) return send(response, 503, { error: 'Add the OpenAI API key to the backend before generating images. No credits were charged.' });
      const payload = await body(request);
      if (!['pet', 'photo', 'background'].includes(payload.kind)) throw new Error('Choose a pet, photo adventure, or widget background.');
      const recipe = payload.kind === 'background' ? null : validateRecipe(payload.recipe);
      const description = payload.kind === 'background' ? validateBackground(payload.prompt) : null;
      if (payload.onboarding !== undefined && typeof payload.onboarding !== 'boolean') throw new Error('Invalid onboarding request.');
      if (payload.onboarding && payload.kind !== 'pet') throw new Error('Your free creation is for a Fur Baby.');
      const key = request.headers['idempotency-key']; if (typeof key !== 'string' || key.length > 100 || key.length < 10) throw new Error('A valid request key is required.');
      const activeCount = ledger.db.prepare("SELECT COUNT(*) AS count FROM jobs WHERE user_id=? AND status='pending'").get(userID).count;
      if (activeCount >= 2 && !ledger.db.prepare('SELECT id FROM jobs WHERE user_id=? AND key=?').get(userID, key)) throw new Error('Wait for your current images to finish first.');
      let pet;
      if (payload.kind === 'photo') { decodeImage(payload.photoBase64); pet = ledger.pet(userID, payload.petID); if (!pet) throw new Error('Choose a pet created on this account.'); if (typeof payload.placement !== 'string' || payload.placement.length > 500) throw new Error('Describe the placement in 500 characters or fewer.'); }
      const { job, isNew } = ledger.reserve(userID, key, hash(JSON.stringify(payload)), payload.kind !== 'pet', payload.onboarding === true, payload.kind === 'background' ? BACKGROUND_PRICE : undefined);
      if (isNew) {
        (async () => {
          try {
            const output = payload.kind === 'pet' ? await images.generate(recipe) : payload.kind === 'background' ? await images.background(description) : await images.photo(payload.photoBase64, pet, payload.placement);
            ledger.logUsage(job.id, payload.kind, output.usage);
            const petID = payload.kind === 'pet' ? ledger.savePet(userID, recipe, output.image) : null;
            ledger.complete(job.id, { imageBase64: output.image, petID });
          } catch { ledger.fail(job.id, 'Image generation could not finish. Reserved credits were returned; please try again.'); }
        })();
      }
      return send(response, 202, { id: job.id });
    }
    const keyMatch = path.match(/^\/v1\/jobs\/by-key\/([a-f0-9-]+)$/i);
    if (keyMatch && request.method === 'GET') {
      const job = ledger.db.prepare('SELECT id FROM jobs WHERE user_id=? AND key=?').get(userID, keyMatch[1]);
      return job ? send(response, 200, job) : send(response, 404, { error: 'The image request was not accepted. No credits were charged; please create it again.' });
    }
    const jobMatch = path.match(/^\/v1\/jobs\/([a-f0-9-]+)$/);
    if (jobMatch && request.method === 'GET') {
      const job = ledger.job(userID, jobMatch[1]); if (!job) return send(response, 404, { error: 'Image request not found.' });
      const result = job.result ? { ...JSON.parse(job.result), wallet: ledger.wallet(userID) } : null;
      if (result?.animation) result.animation = await animations.response(result.petID, result.animation);
      return send(response, 200, { status: job.status, result, error: job.error, progress: job.progress ? JSON.parse(job.progress) : null });
    }
    const animationMatch = path.match(/^\/v1\/pets\/([a-f0-9-]+)\/animations$/);
    if (animationMatch && request.method === 'POST') {
      if (!animationsConfigured) return send(response, 503, { error: 'Add the fal.ai API key to the backend before animating pets. No credits were charged.' });
      if (!ledger.wallet(userID).isPro) throw new Error('Pet animations require Pro.');
      const pet = ledger.pet(userID, animationMatch[1]); if (!pet) throw new Error('Pet not found.');
      const requestedKind = (await body(request)).kind;
      const kind = animationKind(requestedKind);
      if (!Object.hasOwn(ANIMATIONS, kind)) throw new Error('Choose playful, running, sleeping, or idle.');
      const prefix = `animation-${pet.id}-${kind}-`;
      const legacyPrefix = kind === 'playful' ? `animation-${pet.id}-lick-` : prefix;
      const jobs = ledger.db.prepare('SELECT * FROM jobs WHERE user_id=? AND (key LIKE ? OR key LIKE ?) ORDER BY created DESC, rowid DESC').all(userID, prefix + '%', legacyPrefix + '%');
      const pending = jobs.find(job => job.status === 'pending');
      if (pending) return send(response, 202, { id: pending.id });
      const completed = jobs.find(job => job.status === 'completed');
      if (completed && await animations.cached(pet.id, kind)) return send(response, 202, { id: completed.id });
      const active = ledger.db.prepare("SELECT COUNT(*) AS count FROM jobs WHERE user_id=? AND status='pending'").get(userID).count;
      if (active >= 2) throw new Error('Wait for your current creations to finish first.');
      // Cache verification is asynchronous. Recheck after it to make concurrent retries share one reservation.
      const { job, isNew } = ledger.reserve(userID, prefix + jobs.length, hash(`${pet.id}:${kind}:video-v1`), true, false, ANIMATION_PRICE);
      if (isNew) {
        (async () => {
          try {
            const output = await animations.generate(kind, pet, progress => ledger.updateProgress(job.id,
              requestedKind === 'lick' ? { ...progress, kind: requestedKind } : progress));
            ledger.logUsage(job.id, kind, { providers: output.providers, requestIDs: output.requestIDs });
            ledger.complete(job.id, { petID: pet.id, animation: requestedKind === 'lick' ? { ...output, kind: requestedKind } : output });
          } catch { ledger.fail(job.id, 'Animation could not finish. Reserved credits were returned; please try again.'); }
        })();
      }
      return send(response, 202, { id: job.id });
    }
    const poseMatch = path.match(/^\/v1\/pets\/([a-f0-9-]+)\/poses$/);
    if (poseMatch && request.method === 'POST') {
      if (!options.images && !animationsConfigured) return send(response, 503, { error: 'Configure fal.ai before animating pets. No credits were charged.' });
      if (!ledger.wallet(userID).isPro) throw new Error('Pet poses require Pro.');
      const pet = ledger.pet(userID, poseMatch[1]); if (!pet) throw new Error('Pet not found.');
      if (!poseJobs.has(pet.id)) {
        const promise = (async () => {
          for (const kind of ['sleep', 'playful']) if (!pet[kind]) {
            const attempt = ledger.db.prepare('SELECT COUNT(*) AS count FROM jobs WHERE user_id=? AND key LIKE ?').get(userID, `pose-${pet.id}-${kind}-%`).count;
            const { job } = ledger.reserve(userID, `pose-${pet.id}-${kind}-${attempt}`, hash(`${pet.id}:${kind}`), true, false, ANIMATION_PRICE);
            try {
              const output = await (options.images?.pose ? images.pose(kind, pet) : animations.pose(kind, pet));
              ledger.savePose(pet.id, kind, output.image); ledger.logUsage(job.id, kind, output.usage); ledger.complete(job.id, { pose: kind });
            } catch (error) { ledger.fail(job.id, error.message); throw error; }
          }
          const completed = ledger.pet(userID, pet.id);
          return { sleepingBase64: completed.sleep, playfulBase64: completed.playful,
            lickingBase64: completed.playful, wallet: ledger.wallet(userID) }; // Legacy clients.
        })();
        poseJobs.set(pet.id, promise); promise.finally(() => poseJobs.delete(pet.id)).catch(() => {});
      }
      return send(response, 200, await poseJobs.get(pet.id));
    }
    return send(response, 404, { error: 'That route does not exist.' });
  } catch (error) {
    // Do not expose provider bodies, purchase claims, request photos, tokens or keys in responses/logs.
    const message = error.name?.includes('Verification') ? 'The App Store purchase could not be verified.' : error.message;
    send(response, 400, { error: message ?? 'The request could not be completed.' });
  }
});
server.requestTimeout = 630_000;
return { server, ledger };
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
const { server, ledger } = createBackend();
server.listen(Number(process.env.PORT ?? 8787), process.env.HOST ?? '127.0.0.1', () => console.log('My Fur Baby service is listening. Configure the iOS service URL to connect.'));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => { ledger.close(); process.exit(0); }));
}
