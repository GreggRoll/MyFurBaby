# Backend hosting

The backend is deployed at **https://myfurbaby-api-production.up.railway.app** as a single Linux Node.js container with SQLite on a 500 MB persistent volume. [Railway project](https://railway.com/project/1e766e21-4a6b-4ea8-9f70-7fd69c31a39a). The OpenAI key was copied securely from the ignored local `backend/.env` into hosting variables through stdin. It is excluded from the uploaded source, Docker context and image.

## Railway beta deployment

Use the `backend` directory as the upload/build root, with its `Dockerfile` and `railway.json`. Attach one persistent volume at `/data` **before** starting the service. Keep one replica in one region. The database includes accounts, purchases, credit reservations, generated images and usage records; losing the volume loses these records. A redeployment briefly stops the one container.

The image supplies the network binding, data directory, public Apple certificates, registered bundle ID, app ID and Sandbox receipt environment. Configure these service variables separately:

| Variable | Value |
|---|---|
| `OPENAI_API_KEY` | Securely copy the existing server key; never put it in source or build arguments. |
| `FAL_KEY` | Configured privately at runtime for the deployed video pipeline; never included in the image or app. |
| `TRUST_RAILWAY_PROXY` | `true` only when the service is exposed through Railway HTTP ingress. |
| `PORT` | `8787`, matching the HTTPS domain's target port. |
| `HOST` | `::`, accepting both IPv6 and IPv4 connections. |
| `DATA_DIRECTORY` | `/data`, the mounted persistent volume. |

Do not expose a raw TCP proxy or permit untrusted direct access while trusting ingress headers. The service uses the ingress `X-Real-IP` for free-account limits; direct/local mode ignores forwarded headers. The deployed ingress was tested with multiple forged `X-Real-IP` values; all still shared the true client's session limit.

Generate a Railway HTTPS domain and verify `/health` reports both image and purchase configuration. Create a real account, verify authenticated wallet access and verify its persistence after redeploy. Test one actual GPT Image 2 generation and confirm the 250-credit charge. The app connects to the hosted origin by default; developer launches can override it with `FURBABY_SERVICE_URL`. Settings no longer exposes service configuration. TestFlight uses Sandbox purchases. Configure the Apple Sandbox Server Notifications V2 URL as `https://YOUR_HOST/v1/apple/notifications` and complete a genuine Sandbox purchase before calling payments verified.

Deployment checks on October 8, 2026: public HTTPS health reports both integrations configured; unauthenticated wallet access and forged Apple purchase/notification payloads are rejected. A genuine GPT Image 2 pet finished in about 32 seconds, with exactly 250 credits charged and no duplicate charge on an idempotent retry. Account authorization, the completed job, the spent-credit balance and the exact image bytes all survived a live redeployment. The returned PNG is preserved in `docs/live-validation/cloud-pet.png`; sanitized evidence is in `cloud-validation.json`. The Sandbox V2 callback URL was saved in App Store Connect and read back. Apple's request-test-notification API returned HTTP 404 / APP_NOT_FOUND, so genuine signed notification delivery is **not** verified.

## Hosting costs and limits

[Railway's trial](https://docs.railway.com/pricing/free-trial) gives $5 for up to 30 days; when the credit is used or the trial ends, the Free plan gives $1 per month. A limited, unverified trial may restrict outbound API access. Check the existing account's plan and verification status first. The Free/trial persistent-volume limit is 0.5 GB, so this is only a small beta until storage use is measured.

[Hobby pricing](https://docs.railway.com/pricing/plans) starts at $5 per month, includes $5 of resource use and charges additional usage beyond it. Monitor actual RAM, CPU, disk and egress. OpenAI usage is billed separately. No paid subscription or upgrade is authorized just by these deployment files.

At deployment, Railway reported `plan=HOBBY` alongside `isTrialing=true`, $5 of remaining trial usage credit and 30 trial days remaining. No paid upgrade was performed. A $5 hard usage limit was rejected (minimum nonzero limit: $10), and setting $10 was also rejected because an active paid subscription is required. **No usage stop limit is configured.** This service currently relies on the trial allowance; revisit the Free/Hobby choice before it expires.

Keep serverless sleeping disabled initially: requests can be interrupted by sleep/cold starts, and this beta still runs generation work in-process. Once generation is durably queued and wake-up retries are verified, sleeping may reduce idle cost. Do not run frequent external health pings for the purpose of keeping a free service awake.

## Local container verification

```sh
docker build -t myfurbaby-backend:beta backend
node scripts/verify_backend_container.mjs
```

The Docker build runs all backend tests without a real provider key. The smoke check creates a temporary volume and two successive containers, verifying health, authorization, receipt rejection, unchanged credits after rejected requests, secret exclusion and account persistence. It deletes only its own temporary resources. It never calls OpenAI.

Verified October 8, 2026: all 25 tests passed inside Linux Docker, and all smoke checks above passed. The local container measured about 44 MiB idle RAM; this is a development-machine observation, not a cloud billing estimate or peak-generation measurement.

## Beta limitations

This is an early beta with anonymous device accounts and in-process jobs. A server restart refunds pending reservations but may interrupt a provider call already billed by OpenAI. Avoid redeploying during active generation. The new animation route returns a receipt immediately and supports polling and recovery. Older two-sheet pose requests can still outlast the host’s idle HTTP timeout. Video jobs remain in-process; restarts can interrupt an already-billed fal.ai call. The video update was deployed on October 8, 2026; health reports `animationsConfigured: true`. Durable workers, monitored backups, account recovery and production reconciliation remain release work. The persistent volume is storage, not an independently verified backup.

Railway accepted `railway.json` but reports that this configuration format is deprecated and will stop working after December 1, 2026. Migrate to its Infrastructure as Code format before that date. The initial routing issue was resolved by explicitly setting the service's port and dual-stack bind address.

## Animation route deployment verification

Deployment `86d6f5d8-da33-4437-a1cf-41f489e2cd23` fixes the API mismatch affecting Animate my pet in TestFlight 1.0 (8). Before switching containers, there were zero pending jobs, nine accounts and three pets. Runtime `FAL_KEY` was supplied securely over stdin. Only backend source, tests and public Apple certificates were uploaded. The Linux image passed all 34 tests; the local production-style container smoke check confirms the route, FFmpeg VP9 decoding, missing-key credit safety, secret exclusion and persistence through replacement. Live verification confirms configured integrations, an authenticated animation request reaching the Pro guard, unchanged wallet and preserved artwork. No paid generation was performed. See [evidence](live-validation/animation-route-deployment.json).

For future releases that add backend APIs, deploy the matching server first and verify the new authenticated route before distributing the client. A generic healthy response alone does not establish that the client API exists.

## Animation pipeline progress deployment

Deployment `a301825c-986a-4c37-94c7-2db02541ed1b` adds persisted, authenticated animation pipeline progress for client build 11. There were zero pending jobs before deployment. All 35 backend tests passed in the Linux build. Production verification matched the deployed source hashes, confirmed the SQLite progress-column migration and new job-response field, and verified that all nine accounts, four pets, and 21 saved jobs remained available. Existing authenticated account/job access and authorization rejection were checked without a provider generation or credit charge. The temporary SSH key used for verification was revoked. See [sanitized evidence](live-validation/widget-progress-deployment.json).

## Idle animation deployment — October 9, 2026

Deployment `cdf37d60-6c0f-46d6-b7e3-46f94c2b5ddf` adds two-second idle generation and uses PixVerse V6 transition with the same reference at both endpoints for new playback videos. It also includes the current widget customization backend and 1,500-token animation pricing. All 41 backend tests passed during the Linux build. There were zero pending jobs before deployment. Live source hashes matched, configured health checks passed, the animation route's Pro guard rejected a free account without changing its wallet, and authenticated saved-job access and unauthenticated rejection passed. All fourteen existing accounts, five pets and twenty-five saved jobs remained available. No provider generation was performed during deployment validation. Temporary deployment SSH access was revoked. See [sanitized evidence](live-validation/idle-loop-deployment.json).
