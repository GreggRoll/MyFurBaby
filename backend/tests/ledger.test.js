import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import assert from 'node:assert/strict';
import { Ledger, PRODUCTS, addMonths, creditPeriod } from '../ledger.js';

function setup() {
  let now = Date.UTC(2026, 0, 31, 12);
  const ledger = new Ledger(':memory:', () => now), session = ledger.createSession();
  return { ledger, id: session.accountID, now: () => now, advance: value => { now = value; }, tx: (product = PRODUCTS.monthly, transactionId = 'tx-1', expiresDate = addMonths(now, 1)) => ({ transactionId, originalTransactionId: 'original', productId: product, purchaseDate: now, expiresDate, appAccountToken: session.accountID }) };
}
test('monthly credit periods anchor to purchase date across short months', () => {
  const anchor = Date.UTC(2026, 0, 31, 12);
  assert.equal(addMonths(anchor, 1), Date.UTC(2026, 1, 28, 12));
  assert.equal(addMonths(anchor, 2), Date.UTC(2026, 2, 31, 12));
  assert.equal(creditPeriod(anchor, Date.UTC(2026, 1, 28, 11)).id, 0);
  assert.equal(creditPeriod(anchor, Date.UTC(2026, 1, 28, 12)).id, 1);
});
test('one free image, then no negative balance', () => {
  const { ledger, id } = setup();
  ledger.reserve(id, 'first-request', 'payload', false);
  assert.equal(ledger.wallet(id).trialCredits, 0);
  assert.throws(() => ledger.reserve(id, 'another-request', 'payload', false), /250 credits/);
  ledger.close();
});
test('request retries deduct once and reject reuse for a different image', () => {
  const { ledger, id } = setup();
  const first = ledger.reserve(id, 'request-key', 'same', false);
  const retry = ledger.reserve(id, 'request-key', 'same', false);
  assert.equal(retry.job.id, first.job.id); assert.equal(retry.isNew, false);
  assert.throws(() => ledger.reserve(id, 'request-key', 'different', false), /different image/);
  assert.equal(ledger.wallet(id).trialCredits, 0); ledger.close();
});
test('annual membership grants 5000 each month without carrying unused allowance', () => {
  const s = setup(); s.ledger.purchase(s.id, s.tx(PRODUCTS.yearly, 'annual', addMonths(s.now(), 12)));
  s.ledger.reserve(s.id, 'job-one', 'payload', false);
  assert.equal(s.ledger.wallet(s.id).subscriptionCredits, 4750);
  s.advance(addMonths(s.now(), 1));
  assert.equal(s.ledger.wallet(s.id).subscriptionCredits, 5000);
  assert.equal(s.ledger.wallet(s.id).isPro, true); s.ledger.close();
});
test('verified purchase replay cannot award credits twice or transfer accounts', () => {
  const s = setup(), tx = s.tx(PRODUCTS.pack);
  s.ledger.purchase(s.id, tx); s.ledger.purchase(s.id, tx);
  assert.equal(s.ledger.wallet(s.id).purchasedCredits, 5000);
  const other = s.ledger.createSession();
  assert.throws(() => s.ledger.purchase(other.accountID, tx), /another account/);
  assert.equal(s.ledger.wallet(other.accountID).purchasedCredits, 0); s.ledger.close();
});
test('pack credits survive subscription expiry; photo edits require active Pro', () => {
  const s = setup(); s.ledger.purchase(s.id, s.tx()); s.ledger.purchase(s.id, s.tx(PRODUCTS.pack, 'pack'));
  s.advance(addMonths(s.now(), 1)); const wallet = s.ledger.wallet(s.id);
  assert.equal(wallet.isPro, false); assert.equal(wallet.subscriptionCredits, 0); assert.equal(wallet.purchasedCredits, 5000);
  assert.throws(() => s.ledger.reserve(s.id, 'photo', 'payload', true), /requires Pro/);
  s.ledger.reserve(s.id, 'pet', 'payload', false); assert.equal(s.ledger.wallet(s.id).purchasedCredits, 4750); s.ledger.close();
});
test('a lapsed subscriber receives the new allowance on rejoining', () => {
  const s = setup(); s.ledger.purchase(s.id, s.tx()); s.advance(addMonths(s.now(), 1) + 1); s.ledger.wallet(s.id);
  s.ledger.purchase(s.id, s.tx(PRODUCTS.monthly, 'rejoin'));
  assert.equal(s.ledger.wallet(s.id).subscriptionCredits, 5000); s.ledger.close();
});
test('failure refunds exactly once, successful job cannot be refunded', () => {
  const s = setup(); const job = s.ledger.reserve(s.id, 'retry', 'payload', false).job;
  s.ledger.fail(job.id, 'Failed'); s.ledger.fail(job.id, 'Failed again');
  assert.equal(s.ledger.wallet(s.id).trialCredits, 250);
  const completed = s.ledger.reserve(s.id, 'success', 'payload', false).job;
  s.ledger.complete(completed.id, { imageBase64: 'image' }); s.ledger.fail(completed.id, 'late error');
  assert.equal(s.ledger.wallet(s.id).trialCredits, 0); s.ledger.close();
});
test('old-period failure cannot increase a fresh subscription allowance', () => {
  const s = setup(); s.ledger.purchase(s.id, s.tx(PRODUCTS.yearly, 'year', addMonths(s.now(), 12)));
  const job = s.ledger.reserve(s.id, 'old-job', 'payload', false).job;
  s.advance(addMonths(s.now(), 1)); s.ledger.fail(job.id, 'Failed');
  assert.equal(s.ledger.wallet(s.id).subscriptionCredits, 5000); s.ledger.close();
});
test('split-bucket debit refunds the original buckets; interrupted jobs recover', () => {
  const s = setup(); s.ledger.purchase(s.id, s.tx()); s.ledger.purchase(s.id, s.tx(PRODUCTS.pack, 'pack'));
  s.ledger.db.prepare('UPDATE users SET sub_credits=100 WHERE id=?').run(s.id);
  s.ledger.reserve(s.id, 'split', 'payload', false);
  assert.equal(s.ledger.wallet(s.id).subscriptionCredits, 0); assert.equal(s.ledger.wallet(s.id).purchasedCredits, 4850);
  s.ledger.recoverInterrupted();
  assert.equal(s.ledger.wallet(s.id).subscriptionCredits, 100); assert.equal(s.ledger.wallet(s.id).purchasedCredits, 5000); s.ledger.close();
});
test('refunded credit pack cannot be reclaimed with purchase replay', () => {
  const s = setup(), tx = s.tx(PRODUCTS.pack); s.ledger.purchase(s.id, tx); s.ledger.revoke(tx); s.ledger.revoke(tx); s.ledger.purchase(s.id, tx);
  assert.equal(s.ledger.wallet(s.id).purchasedCredits, 0); s.ledger.close();
});

test('existing pose column migrates to playful without losing saved artwork', t => {
  const directory = mkdtempSync(join(tmpdir(), 'fur-pose-migration-')), path = join(directory, 'old.sqlite');
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const db = new DatabaseSync(path);
  db.exec("CREATE TABLE pets(id TEXT PRIMARY KEY, user_id TEXT, recipe TEXT, image TEXT, sleep TEXT, lick TEXT)");
  db.prepare('INSERT INTO pets VALUES(?,?,?,?,?,?)').run('pet', 'user', '{}', 'original', 'sleeping', 'saved-action');
  db.close();
  const ledger = new Ledger(path);
  assert.equal(ledger.pet('user', 'pet').playful, 'saved-action');
  assert.equal(ledger.pet('user', 'pet').sleep, 'sleeping');
  ledger.close();
  const reopened = new Ledger(path);
  assert.equal(reopened.pet('user', 'pet').playful, 'saved-action');
  reopened.close();
});
