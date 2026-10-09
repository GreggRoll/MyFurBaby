import { DatabaseSync } from 'node:sqlite';
import { randomBytes, randomUUID, createHash } from 'node:crypto';

export const PRICE = 250;
export const BACKGROUND_PRICE = 200;
export const ANIMATION_PRICE = 1500;
export const ALLOWANCE = 5000;
export const PRODUCTS = { monthly: 'ProMonthly499', yearly: 'ProYearly4999', pack: '500CreditPack' };
export const hash = value => createHash('sha256').update(value).digest('hex');

export function addMonths(anchor, months) {
  const original = new Date(anchor), first = new Date(anchor);
  first.setUTCDate(1); first.setUTCMonth(first.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
  first.setUTCDate(Math.min(original.getUTCDate(), lastDay));
  return first.getTime();
}
export function creditPeriod(anchor, now) {
  let month = Math.max(0, (new Date(now).getUTCFullYear() - new Date(anchor).getUTCFullYear()) * 12 + new Date(now).getUTCMonth() - new Date(anchor).getUTCMonth());
  if (addMonths(anchor, month) > now) month--;
  return { id: Math.max(0, month), next: addMonths(anchor, Math.max(0, month) + 1) };
}

export class Ledger {
  constructor(path = ':memory:', now = () => Date.now()) {
    this.now = now; this.db = new DatabaseSync(path);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, token_hash TEXT UNIQUE, sub_start INTEGER, sub_end INTEGER,
      period INTEGER DEFAULT -1, sub_credits INTEGER DEFAULT 0, pack_credits INTEGER DEFAULT 0, trial_credits INTEGER DEFAULT 250);
      CREATE TABLE IF NOT EXISTS purchases(id TEXT PRIMARY KEY, user_id TEXT, product TEXT, original_id TEXT, claims TEXT, revoked INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, user_id TEXT, key TEXT, payload_hash TEXT, status TEXT,
      sub_debit INTEGER, pack_debit INTEGER, trial_debit INTEGER, debit_period INTEGER, result TEXT, error TEXT, created INTEGER, UNIQUE(user_id,key));
      CREATE TABLE IF NOT EXISTS pets(id TEXT PRIMARY KEY, user_id TEXT, recipe TEXT, image TEXT, sleep TEXT, playful TEXT);
      CREATE TABLE IF NOT EXISTS usage(id INTEGER PRIMARY KEY, job_id TEXT, kind TEXT, usage TEXT, created INTEGER);`);
    if (!this.db.prepare('PRAGMA table_info(jobs)').all().some(column => column.name === 'progress')) {
      this.db.exec('ALTER TABLE jobs ADD COLUMN progress TEXT');
    }
    const petColumns = this.db.prepare('PRAGMA table_info(pets)').all();
    if (!petColumns.some(column => column.name === 'playful')) {
      this.db.exec('ALTER TABLE pets RENAME COLUMN lick TO playful');
    }
  }
  close() { this.db.close(); }
  atomic(work) {
    this.db.exec('BEGIN IMMEDIATE');
    try { const result = work(); this.db.exec('COMMIT'); return result; }
    catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  createSession() {
    const id = randomUUID(), token = randomBytes(32).toString('base64url');
    this.db.prepare('INSERT INTO users(id,token_hash) VALUES(?,?)').run(id, hash(token));
    return { accountID: id, token, wallet: this.wallet(id) };
  }
  authenticate(token) { return this.db.prepare('SELECT id FROM users WHERE token_hash=?').get(hash(token))?.id; }
  user(id) { const user = this.db.prepare('SELECT * FROM users WHERE id=?').get(id); if (!user) throw new Error('Account not found.'); return user; }
  refresh(id) {
    let user = this.user(id), now = this.now();
    if (!user.sub_end || user.sub_end <= now) {
      this.db.prepare('UPDATE users SET sub_credits=0 WHERE id=?').run(id);
    } else {
      const period = creditPeriod(user.sub_start, now);
      if (user.period !== period.id) this.db.prepare('UPDATE users SET period=?,sub_credits=? WHERE id=?').run(period.id, ALLOWANCE, id);
    }
    return this.user(id);
  }
  wallet(id) {
    const user = this.refresh(id), isPro = !!user.sub_end && user.sub_end > this.now();
    return { accountID: id, isPro, subscriptionCredits: user.sub_credits, purchasedCredits: user.pack_credits,
      trialCredits: isPro ? 0 : user.trial_credits,
      resetsAt: isPro ? new Date(Math.min(creditPeriod(user.sub_start, this.now()).next, user.sub_end)).toISOString() : null,
      expiresAt: user.sub_end ? new Date(user.sub_end).toISOString() : null };
  }
  purchase(id, tx) {
    return this.atomic(() => {
      if (!tx.transactionId || !Object.values(PRODUCTS).includes(tx.productId)) throw new Error('Unknown purchase.');
      if (tx.appAccountToken?.toLowerCase() !== id.toLowerCase()) throw new Error('This purchase belongs to another account. Use the original connected account.');
      const existing = this.db.prepare('SELECT * FROM purchases WHERE id=?').get(tx.transactionId);
      if (existing && existing.user_id !== id) throw new Error('This purchase has already been used by another account.');
      if (existing) return this.wallet(id);
      if (tx.revocationDate) throw new Error('This purchase was refunded or revoked.');
      if (tx.productId !== PRODUCTS.pack && (!Number.isFinite(tx.expiresDate) || tx.expiresDate <= this.now())) throw new Error('This subscription has expired.');
      this.db.prepare('INSERT INTO purchases(id,user_id,product,original_id,claims) VALUES(?,?,?,?,?)').run(tx.transactionId, id, tx.productId, tx.originalTransactionId ?? tx.transactionId, JSON.stringify(tx));
      if (tx.productId === PRODUCTS.pack) this.db.prepare('UPDATE users SET pack_credits=pack_credits+? WHERE id=?').run(ALLOWANCE, id);
      else {
        const user = this.user(id);
        const continuing = !!user.sub_start && user.sub_end > this.now();
        const anchor = continuing ? user.sub_start : (tx.purchaseDate ?? this.now());
        this.db.prepare('UPDATE users SET sub_start=?,sub_end=?,period=?,trial_credits=0 WHERE id=?').run(anchor, Math.max(user.sub_end ?? 0, tx.expiresDate), continuing ? user.period : -1, id);
      }
      return this.wallet(id);
    });
  }
  revoke(tx) {
    return this.atomic(() => {
      const purchase = this.db.prepare('SELECT * FROM purchases WHERE id=?').get(tx.transactionId);
      if (!purchase || purchase.revoked) return;
      this.db.prepare('UPDATE purchases SET revoked=1 WHERE id=?').run(tx.transactionId);
      if (purchase.product === PRODUCTS.pack) this.db.prepare('UPDATE users SET pack_credits=MAX(0,pack_credits-?) WHERE id=?').run(ALLOWANCE, purchase.user_id);
      else this.db.prepare('UPDATE users SET sub_end=?,sub_credits=0 WHERE id=?').run(this.now(), purchase.user_id);
    });
  }
  reserve(id, key, payloadHash, requiresPro, onboarding = false, price = PRICE) {
    if (!Number.isSafeInteger(price) || price <= 0 || (onboarding && price !== PRICE)) throw new Error('Invalid creation price.');
    return this.atomic(() => {
      const existing = this.db.prepare('SELECT * FROM jobs WHERE user_id=? AND key=?').get(id, key);
      if (existing) { if (existing.payload_hash !== payloadHash) throw new Error('This request key was used for a different image.'); return { job: existing, isNew: false }; }
      const user = this.refresh(id), isPro = user.sub_end > this.now();
      if (requiresPro && !isPro) throw new Error('This creation requires Pro.');
      const available = user.sub_credits + user.pack_credits + (isPro ? 0 : user.trial_credits);
      if (onboarding && (requiresPro || user.trial_credits < PRICE)) throw new Error('This account’s free Fur Baby has already been created.');
      if (!onboarding && available < price) throw new Error(`You need ${price} credits for this creation.`);
      let left = price;
      const sub = onboarding ? 0 : Math.min(left, user.sub_credits); left -= sub;
      const trial = onboarding ? PRICE : !isPro ? Math.min(left, user.trial_credits) : 0; left -= trial;
      const pack = left;
      this.db.prepare('UPDATE users SET sub_credits=sub_credits-?,pack_credits=pack_credits-?,trial_credits=trial_credits-? WHERE id=?').run(sub, pack, trial, id);
      const jobID = randomUUID();
      this.db.prepare('INSERT INTO jobs(id,user_id,key,payload_hash,status,sub_debit,pack_debit,trial_debit,debit_period,created) VALUES(?,?,?,?,?,?,?,?,?,?)').run(jobID, id, key, payloadHash, 'pending', sub, pack, trial, user.period, this.now());
      return { job: this.job(id, jobID), isNew: true };
    });
  }
  job(userID, id) { return this.db.prepare('SELECT * FROM jobs WHERE id=? AND user_id=?').get(id, userID); }
  updateProgress(id, progress) { this.db.prepare("UPDATE jobs SET progress=? WHERE id=? AND status='pending'").run(JSON.stringify(progress), id); }
  complete(id, result) { this.db.prepare("UPDATE jobs SET status='completed',result=? WHERE id=? AND status='pending'").run(JSON.stringify(result), id); }
  fail(id, message) {
    this.atomic(() => {
      const job = this.db.prepare('SELECT * FROM jobs WHERE id=?').get(id);
      if (!job || job.status !== 'pending') return;
      const user = this.refresh(job.user_id), samePeriod = user.period === job.debit_period && user.sub_end > this.now();
      this.db.prepare('UPDATE users SET sub_credits=sub_credits+?,pack_credits=pack_credits+?,trial_credits=trial_credits+? WHERE id=?').run(samePeriod ? job.sub_debit : 0, job.pack_debit, job.trial_debit, job.user_id);
      this.db.prepare("UPDATE jobs SET status='failed',error=? WHERE id=?").run(message, id);
    });
  }
  recoverInterrupted() { for (const job of this.db.prepare("SELECT id FROM jobs WHERE status='pending'").all()) this.fail(job.id, 'The service restarted. Credits were returned; please try again.'); }
  pet(userID, id) { return this.db.prepare('SELECT * FROM pets WHERE user_id=? AND id=?').get(userID, id); }
  savePet(userID, recipe, image) { const id = randomUUID(); this.db.prepare('INSERT INTO pets(id,user_id,recipe,image) VALUES(?,?,?,?)').run(id, userID, JSON.stringify(recipe), image); return id; }
  savePose(id, kind, value) { this.db.prepare(`UPDATE pets SET ${kind === 'sleep' ? 'sleep' : 'playful'}=? WHERE id=?`).run(value, id); }
  logUsage(jobID, kind, usage) { this.db.prepare('INSERT INTO usage(job_id,kind,usage,created) VALUES(?,?,?,?)').run(jobID, kind, JSON.stringify(usage ?? {}), this.now()); }
}
