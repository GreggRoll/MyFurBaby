# First-run onboarding

The onboarding flow was released October 8, 2026 as TestFlight 1.0 (3). Build 4 adds connection recovery and rolling creation messages and is processed VALID and available in Internal Testing. The matching backend update is deployed and verified; build 4 requires no server changes.

1. Welcome: “Hi! You’re about to create your very own Fur Baby.”
2. Silent looping demo: photo adventures, then a cozy hangout.
3. Silent looping demo: small and medium widget layouts.
4. “Let’s start with some questions.”
5. Five questions: Boy/Girl, species, color, optional accessories, initial name. Questions use he/his or she/her. Personality defaults to playful, affectionate, and curious.
6. A magical egg with orbiting hearts and sparkles while the free image is created. Messages scroll every three seconds, including “Building toe beans…” and “Filling them with love…”. Interrupted connections retry automatically; pending requests resume without a second reservation.
7. Reveal the created pet and confirm or change the initial name.
8. Show the existing Pro paywall with the saved pet, name, and pronoun. “Not now” completes onboarding while keeping the pet.

Progress, answers, created pet ID, and completion persist separately for sample and connected modes. Before rendering the first screen, connected-mode launches check the saved Keychain session for the configured service. A returning account bypasses onboarding even if local pets or preferences are missing or the saved onboarding stage is incomplete. First-time users without a saved session see onboarding; creating their initial anonymous session during startup does not skip it in the current run. The service validates the saved account through its wallet endpoint afterward and never replaces a failed existing session with a new account. Sample mode remains isolated from connected accounts. Interrupted image jobs remain recoverable in Settings, with the original pet name retained. This uses the device-local account identity; cross-device account restoration is not implemented. This launch-routing change is included in TestFlight 1.0 (8), processed as VALID and available in Internal Testing.

Creation uses the account’s existing 250-credit free allowance. The client marks onboarding generation with `onboarding: true`; the updated backend reserves only the free allowance and cannot spend subscription or purchased credits. Same-key requests are idempotent, failures refund the allowance, and a second free creation is rejected. Additional creations retain their existing credit pricing. Optional recipe gender is validated and retained by the backend; legacy recipes decode without it.

New installations default to the existing hosted HTTPS backend. Nonempty saved service URLs and `FURBABY_SERVICE_URL` overrides still take precedence. The hosted backend retains gender and enforces the explicit onboarding-only allowance restriction. The app does not grant free generation locally in connected mode.

## Demo assets

`Resources/Onboarding/onboarding-adventures.mp4` and `onboarding-widgets.mp4` are bundled seven-second H.264 demos built from the previously validated artwork. They are labeled demo previews. The widget clip demonstrates layouts and does not promise automatic Home Screen motion. Playback stops offscreen or in the background; Reduce Motion pauses playback and the birth animation. Posters provide a static fallback. Regenerate the demos with `scripts/generate_onboarding_videos.py` using Python with Pillow and ffmpeg, then run `python3 scripts/generate_project.py` to refresh project membership.

## Connection recovery — build 4

The reported timeout happened while the server was creating the image; server logs confirmed that the original image completed. The client now gives job responses up to 120 seconds and retries transient network and HTTP failures up to four attempts with short backoff. Creation submissions reuse their saved idempotency key and exact payload; polling and recovery use the original job. The pending request survives an extended outage or app relaunch. Returning to the foreground resumes an unfinished onboarding creation. If retries are exhausted, onboarding shows a friendly inline message and recovery button instead of a raw timeout alert. The backend is unchanged.

Rolling messages stop offscreen and in the background, use a fade with Reduce Motion, and expose a stable progress label to VoiceOver.

## Verification

- Current local account-routing update: 37 iOS tests passed. Regression coverage verifies that a saved account skips onboarding without local pets/progress, overrides stale creation progress while preserving answers, persists completion, checks the configured service only, keeps first-time and sample onboarding intact, and validates an existing account with GET /v1/wallet without creating another session. This change is included in TestFlight build 8; Apple verification confirms VALID, IN_BETA_TESTING, assignment to the existing Internal Testing group, and exact en-US testing-note readback.
- Simulator build passed; 18 iOS tests passed. Seven network regression tests cover poll timeouts, lost submission responses, retries with the same key and body, relaunch recovery with and without a receipt, transient versus permanent failures, continued processing, and terminal provider errors.
- An isolated connected Simulator walkthrough injected a sustained HTTP 503 outage. It displayed the rolling reconnecting messages and then the inline recovery state with no alert. Once the test connection recovered, the original pet appeared at the reveal; the mock server recorded exactly one creation submission across both attempts. No provider call or purchase was made.
- All 27 backend tests passed, including free generation with a purchased credit pack, duplicate requests, failure refunds, retry, and gender validation.
- iPhone 17 Pro / iOS 26.3 sample walkthrough exercised all screens, optional accessories, girl pronouns, changing Luna to Lulu at reveal, and the personalized paywall.
- Relaunch at the accessories question retained answers. Relaunch at the paywall retained its pet and name. After “Not now,” relaunch returned to the saved pet gallery.
- Final intro layouts were visually inspected with both adventure/hangout messages visible and both widget sizes shown.
- Hosted `/health` returned `status: ok`, `imagesConfigured: true`, and `purchasesConfigured: true`. This work did not make a paid provider call or an App Store purchase.
- Screenshots: `docs/screenshots/onboarding/`.

For an isolated sample walkthrough, launch the Debug app with `FURBABY_SAMPLE_MODE=true` and a fresh `FURBABY_STORAGE_SUITE` value. This leaves the existing saved gallery and wallet in their original preferences suite. For local backend testing, set `FURBABY_SERVICE_URL=http://localhost:8787`.

## Shared form for additional pets — October 8, 2026

“Dream up another pet” now uses the same five-question component as onboarding: gender, species, color, optional accessories, and initial name. Both flows validate the same answer limits and use he/his or she/her throughout. Personality uses the same playful default. Additional pets send the gender and initial name without the onboarding flag and cost 250 credits; the reveal retains the initial name and allows editing it. Gender is present in the design JSON and explicitly directed in both image prompt implementations. Legacy recipes without gender remain compatible. The My Pet screen no longer shows the Made with imagination/Sample experience and Pro badges.

All 46 iOS tests passed, including paid creation payloads with gender/name, prompt gender, and retrying a failed sleep animation. All 35 backend tests and the Linux container smoke checks passed. Simulator visuals covered the My Pet layout, gender selection, and pronoun changes. These client changes are local and require a new app build to reach TestFlight.
