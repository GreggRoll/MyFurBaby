# My Fur Baby

Local update (October 9): the widget action is named Playful, with species-appropriate motion and optional licking. Frame handoffs tolerate a display refresh, timeline reloads preserve phase, and previews predecode their saved sequences. Existing pet data and paid animations remain usable. This update is not yet deployed or uploaded to TestFlight.

**Widget studio (TestFlight 1.0 (12)):** Custom backgrounds can be described, generated for 200 tokens, recovered after interruptions, and selected from a saved gallery. Medium widgets offer Pet Info, Clock, Daily Quote, or Calendar on the right. Animation generation costs 1,500 tokens per missing animation. Daily Quote now fetches from ZenQuotes once per local day and includes the author and linked source attribution, with a shared offline cache. A live Swift service fetch was verified. All 63 iOS and 41 backend tests passed. The backend is deployed and build 12 is available in Internal Testing. See [implementation and validation](WIDGET_CUSTOMIZATION.md).

**TestFlight 1.0 (12):** Available in Internal Testing. Awake pets play an action followed by ten seconds of cute idle movement; Sleepy loops sleeping/snoring continuously. New playback videos use the same reference at both endpoints. Animate creates only missing idle/action/sleep clips at 1,500 tokens each. The matching build 12 backend is live, and testing notes are published. See [release verification](TESTFLIGHT_RELEASE.md).

A native SwiftUI iOS MVP with a WidgetKit extension and a Node.js image-and-credit service. Open `MyFurBaby.xcodeproj`, select the **MyFurBaby** scheme and an iPhone Simulator, and run. Requires Xcode 15+ and iOS 17+; verified here with Xcode 26.3 and an iPhone 17 Pro Simulator running iOS 26.3.

**Account-aware launch (TestFlight 1.0 (8)):** The app checks its saved Keychain account before rendering onboarding. Returning accounts go straight into the app even when local pets or onboarding preferences are missing; first-time users still see onboarding. All 37 iOS tests pass. Build 8 is processed and available in Internal Testing, with updated What to Test notes. See [launch routing and verification](ONBOARDING.md).

**Adventure gallery and widget backgrounds (TestFlight 1.0 (7)):** New completed and recovered photo adventures save automatically to an in-app gallery below the generation controls. Reopen memories to share or save to Photos. Widgets now offer Clear, a solid color from the native picker, a cozy living room, and a cyberpunk bedroom, with saved selections shared by both preview sizes and the widget extension. All 32 iOS tests pass. Build 7 is processed and available in Internal Testing; What to Test notes are published. See [behavior, artwork prompts, and screenshots](GALLERY_AND_WIDGET_BACKGROUNDS.md).

**Video animation workflow:** Pet animation uses fal.ai PixVerse V6 transition with the same reference at both endpoints → VEED background removal → fixed-canvas RGBA PNG frames. The playful action is 3 seconds (45 frames), running and sleeping are 4 seconds each (60 frames), all at 15 FPS. Future sleeping generation uses a back/side reclining pose, pronounced visual snoring, and floating Zs composited after background removal. The app and widget play saved frames at 15 FPS. Awake pets play an action, then a two-second idle loop repeated for ten seconds; sleeping/snoring loops continuously. New idle generation costs 1,500 tokens and saved replay is free. The action/idle workflow is included in TestFlight build 12; see [widget playback details](WIDGET_ANIMATION.md). The matching video-animation backend was deployed and verified on October 8, 2026, resolving the missing route when tapping Animate my pet. See [video pipeline details](VIDEO_ANIMATION.md).

**Widget animation beta (TestFlight 1.0 (6)):** Available in Internal Testing, with all 26 iOS tests passing. Addresses the placeholder puppy and gray name bar reported when motion was enabled in build 5. The widget uses saved image frames with Bryce Bostwick’s bundled timer mask. Open the app after upgrading to regenerate frames, then test Playful and Sleepy on your Home Screen. Continuous animation on physical devices remains unverified. See [implementation and testing details](WIDGET_ANIMATION.md).

**Onboarding update (TestFlight 1.0 (4)):** The new first-run flow adds a welcome, adventure/hangout and widget demo videos, five gender-aware questions, a free birth animation and generation, name confirmation, and a personalized Pro paywall. New installs connect to the hosted service automatically. Progress resumes across launches; existing owners go straight to their gallery. The current source passes 18 iOS tests; the deployed backend passed 27 tests. Build 4 adds automatic connection retries, saved-job recovery, and scrolling creation messages including “Building toe beans…” and “Filling them with love…”. See [onboarding behavior and verification](ONBOARDING.md). Build 1.0 (4) is processed and available in Internal Testing; the matching backend is deployed and verified.

**Previously uploaded build status:** version 1.0 (2) is uploaded to TestFlight, processed as VALID and available in the Internal Testing group. Beta notes are published. The app builds and runs, with 6 passing iOS tests and 25 passing backend tests. The four-question flow, naming, sample Pro unlock and both widget layouts were exercised in Simulator. The app also connected to the real local service and displayed its missing-key error without deducting credits. Live GPT Image 2 generation has now been verified through the actual app: a new pet was saved and exactly 250 trial credits were charged. Two real reference-based animation sheets and a two-reference photo insertion were also generated and inspected. Apple Sandbox purchases remain untested. Automatic animation in the actual Home Screen widget stayed still in the simulator experiment and remains an unmet product requirement.

## Explore immediately

The app defaults to the hosted HTTPS service. For a no-charge Debug UI walkthrough, launch with `FURBABY_SAMPLE_MODE=true` and an isolated `FURBABY_STORAGE_SUITE` value. Create a pet, answer the five questions (including gender), confirm its name, and select **Try Pro in sample mode · no charge** on the paywall. Pro gives 5,000 sample credits. Explore playful movement, belly-up sleeping, small and wide widget previews, the gallery and photo picker. The sample generator draws a puppy or cat; it does not claim to render every requested species or accessory. Photo insertion requires the connected image service and explicitly reports that limitation in sample mode.

On the Simulator Home Screen, hold the My Fur Baby app icon and select the small or medium widget, or enter Home Screen editing and choose Add Widget. The widget loads the selected pet and membership state from the App Group. Keep simulator code signing enabled so that group entitlements are registered. If building inside an iCloud-synced Desktop folder causes a codesign “resource fork” error, put Derived Data outside Desktop; this project was built using `/tmp/MyFurBaby-DerivedData`.

Release builds always use connected mode and cannot grant sample Pro or sample credits. Sample and connected galleries/wallets are saved separately. Debug environment overrides `FURBABY_SERVICE_URL` and `FURBABY_SAMPLE_MODE=false` are available for local testing.

## Connect GPT Image 2

The app never contains an OpenAI API key. The service makes all generation and editing requests, validates the credit balance, and stores the ledger in SQLite.

```sh
cd backend
npm ci
cp .env.example .env
```

This workspace already has a configured, ignored `backend/.env`; do not overwrite it. The copy command above is for a fresh checkout. Edit `backend/.env` privately and set `OPENAI_API_KEY` to a project API key with access to `gpt-image-2`. Keep `.env` out of source control. Set a spending limit on that OpenAI project. Then run:

```sh
npm start
```

For local Simulator development, launch with `FURBABY_SERVICE_URL=http://localhost:8787` and `FURBABY_SAMPLE_MODE=false`. The Image service section has been removed from Settings. A physical iPhone needs an HTTPS service reachable from that phone; `localhost` on the phone is not your Mac. The default backend binds only to `127.0.0.1`. Deploy behind HTTPS and keep the database on persistent storage before connecting real devices.

Pet creation and photo insertion use GPT Image 2, medium quality, 1024×1024 PNG. The backend requests opaque white pet artwork and removes border-connected white while preserving enclosed white details. Photo adventures remain opaque and use the photo followed by the exact pet reference. Animation uses fal.ai PixVerse V6 and VEED video background removal; it does not regenerate the pet as separate images. Configure `FAL_KEY` privately in the ignored backend environment and install FFmpeg with `libvpx-vp9` decoding. The Docker image includes FFmpeg.

The prompt templates live in `backend/prompts.js`. They treat the four free-text answers as design data, preserve the species/colors/accessories, and use personality for expression. Client input checks are repeated on the server. Real generated examples and provider token usage are in `docs/live-validation`. API contract tests still use an injected fake provider; a separate image test checks background removal.

## Pro, pricing and credits

The backend now has a Linux Docker deployment package and a persistent-volume smoke check. See [backend hosting setup](BACKEND_DEPLOYMENT.md) for Railway configuration and free-trial limits. The service is live at `https://myfurbaby-api-production.up.railway.app`, using Railway trial credits. Current builds connect to this origin by default.

| Product ID | Product | USD price |
| --- | --- | --- |
| `ProMonthly499` | Auto-renewing monthly Pro | $4.99 |
| `ProYearly4999` | Auto-renewing annual Pro | $50 |
| `500CreditPack` | Consumable 5,000-credit pack | $4.99 |

Both subscriptions receive **5,000 credits per subscription month**, including the annual plan. Unused subscription credits expire at reset. Purchased pack credits do not expire. A free account receives one 250-credit starter generation. Pro gates animation generation, photo insertion and widget access; buying a pack alone does not grant Pro.

A pet still or photo adventure costs **250 credits**. A custom widget background costs **200 tokens** and can be saved and reused for free. Each complete video animation costs **1,500 tokens**. The widget requests idle, playful and sleeping, costing up to 4,500 tokens together; Running is temporarily removed. The Animate button shows the cost of missing animations and loading bars driven by each animation’s pipeline stages. Completed animations are cached and replay without additional credits. Provider video and segmentation charges are billed separately to the fal.ai account.

Subscription credits are spent before purchased credits. Server-side reservations are atomic. Idempotency keys prevent duplicate charges on request retries. Failed jobs return their original credit buckets; old monthly credits are not resurrected after their expiry. Successful image jobs can be recovered from Settings after a connection failure or app restart. A partially successful animation package saves its completed sheet; retrying generates only the missing sheet. Backend usage records can be used to measure actual provider costs.

## Enable real Apple purchases

The local service now has Apple's public root CA certificates configured for Sandbox verification. `/health` reports `purchasesConfigured: true`; malformed signed transactions are rejected. A real Apple-signed Sandbox purchase has not yet been completed. Signing, product availability and an end-to-end purchase test remain to be checked.

Select your developer team for the app and extension. Register bundle IDs `com.gregadams.myfurbaby` and `com.gregadams.myfurbaby.widget`, and App Group `group.com.gregadams.myfurbaby.shared` for both. If you rename these identifiers, update both entitlements, `SharedStorage.group`, project settings and backend `APPLE_BUNDLE_ID` together.

The product IDs above now match the products supplied from App Store Connect. Keep both subscriptions in one Pro subscription group. `500CreditPack` awards 5,000 credits despite the shorter number in its identifier. The app displays the actual localized price returned by StoreKit; identifiers do not determine prices. Configure the USD base prices and localization. The UI uses StoreKit's localized prices when products are available. Set the service's Apple verification configuration:

- `APPLE_BUNDLE_ID=com.gregadams.myfurbaby`
- `APPLE_ENVIRONMENT=Sandbox` while testing; use `Production` for production receipts.
- `APPLE_ROOT_CA_PATHS`: comma-separated absolute paths to the Apple root certificate files downloaded from [Apple's certificate authority](https://www.apple.com/certificateauthority/).
- `APPLE_APP_ID`: the numeric App Store app ID; required for production verification.

Restart the service after changing `.env`. Configure the App Store Server Notifications V2 URL as `https://YOUR_HOST/v1/apple/notifications` for the appropriate environment. The server uses Apple's official library to verify signed transactions and notifications. A transaction must include the account's `appAccountToken`. A verified subscription unlocks Pro; a verified consumable awards credits once. The client finishes a transaction only after the server accepts it. Missing verification configuration rejects purchase activation rather than trusting client flags.

`Resources/Products.storekit` and the **MyFurBabyStoreKit** scheme provide local product/price testing in Xcode. Xcode-local transactions are not Apple Sandbox-signed transactions; the production verifier intentionally does not accept them. Use sample mode for a no-charge UI walkthrough and App Store Sandbox/TestFlight to validate server-backed purchasing. Restore purchases currently requires the original backend account on this device.

## Animation implementation and its limits

Build 1.0 (6) uses ordinary saved image frames with the original demo’s bundled ligature timer mask. It removes dynamically registered artwork fonts from the widget rendering path to address the device placeholder failure. The current client enables automatic motion for all eligible widgets and removes the opt-in control and explanatory text. Opening the app prepares saved frames even if the old motion preference was off. Reduce Motion and dimmed displays retain a still-pose fallback. Physical-device looping remains unverified. See [implementation and device test instructions](WIDGET_ANIMATION.md).

Each behavior starts with the canonical pet PNG. PixVerse generates one continuous clip, VEED extracts the animal with VP9 alpha, and FFmpeg decodes it using `libvpx-vp9`. Frames retain one 512×512 canvas, positioning and scale; no per-frame bounding-box cropping is performed. The original cutout is preserved byte-for-byte. Foreground playback uses all frames at 15 FPS with no additional synthetic rotation or breathing scale. Legacy four-cell artwork still loads for existing pets. Loop seams and appearance need visual review; an AI prompt does not guarantee them. See [pipeline configuration, storage and validation](VIDEO_ANIMATION.md).

Foreground previews animate with SwiftUI. WidgetKit uses persisted entries for mood changes and Pro expiry. The previous timer/font-mask experiment used an original generated font and public view APIs; it included no private clock API or binary framework. **That previous experiment did not animate on iOS 26.3 Simulator.** Small widgets loaded the correct pet, but five successive screenshots were identical. Automatic looping is essential in the brief and remains unresolved. Validate any replacement on current physical devices, including Reduce Motion, low power, app termination and membership expiry, before making it a paid feature promise.

## Verification

```sh
cd backend
npm test
```

The backend tests cover credit period boundaries, annual monthly allowance, rejoining after expiry, purchase/account replay checks, split-bucket refunds, restart recovery, HTTP authentication, trusted ingress addresses, private job recovery, partial animation retry, and generation/edit request shape. Provider calls are mocked; Apple's cryptographic verifier is not mocked into accepting client purchases.

Run **Product → Test** in Xcode with the MyFurBaby scheme. Six tests cover free-text validation, prompt construction, Pro expiry, credit totals, widget persistence and animation-sheet cropping. The generated app and extension both compile successfully. Simulator walkthrough evidence is in `docs/screenshots`; see `docs/VERIFICATION.md` for the recorded checks.

The project is included as a normal `.xcodeproj` and requires no project generator to open. To regenerate after adding sources, run `python3 scripts/generate_project.py`. To reinstall the approved puppy app icon and shared brand images, run `swift scripts/generate_assets.swift`; its source is `Resources/Branding/my-fur-baby-icon.png`. The same artwork appears in the app header, onboarding, Pro, Settings, and widget empty state. Xcode derives the Home Screen, Settings, Spotlight, and App Store icon sizes from the opaque 1024-pixel app icon. To regenerate the blink font, run `python3 scripts/generate_blink_font.py` (requires `fonttools`). Regenerating the project resets project-level manual signing edits, so keep a record of your team settings.

## Before a public paid release

Version 1.0 (2) was successfully uploaded to TestFlight on October 8, 2026. This remains an early MVP. Its HTTPS backend is now hosted on Railway with persistent SQLite storage; build 2 requires configuring the service URL in Settings. A real hosted image and its exact 250-credit charge were verified. No App Store release has been submitted. Required next work is broader visual validation across species/photos, Sandbox purchase/notification tests, and a decision on reliable automatic widget motion. A public service also needs durable background workers, account recovery across devices, Apple transaction reconciliation after missed notifications, abuse-resistant free trials, spend controls, monitoring and backups. The current anonymous session uses a device-local Keychain credential; new devices cannot restore an old account or transfer its purchased credits.

Uploaded source photos are processed in memory and are not stored as source uploads in SQLite. Generated photos, pets, recipes, usage and purchase records are stored without an automatic retention/deletion policy yet. Photos and prompts are also sent to OpenAI, and pet animation references and video are sent to fal.ai/PixVerse/VEED; do not promise zero provider retention. Publish an accurate privacy policy and support/contact URLs, implement data deletion and retention, complete App Store privacy declarations, and review the included privacy manifest before release. It declares app-functionality use of photos, user content, account identifiers and purchase history, with no tracking.

The updated product and cost model is in `PROJECT_PLAN.md`. Current medium output-only costs can support the credit pricing, but real edit input costs, failed calls and acquisition cost must be measured before assuming profit.
