# TestFlight release — October 9, 2026

**My Fur Baby 1.0 (12) is uploaded, processed and available in Internal Testing.**

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6820522244/testflight/ios).

Build 12 replaces the twenty-second final-frame hold with ten seconds of cute idle movement between awake actions. A new two-second idle clip repeats five times, so licking has a thirteen-second action/idle cycle. Sleepy loops sleeping/snoring continuously. New playback videos pass the same reference to PixVerse V6 transition as both start and end frames. Existing clips remain saved; Animate requests only missing idle/lick/sleep clips at 1,500 tokens each (up to 4,500 for a new set). Widget frames rebuild locally at 192 pixels to stay within the timeline archive limit without changing saved full-quality videos.

The release also includes custom generated widget backgrounds, the saved background gallery, medium-widget Pet Info/Clock/Daily Quote/Calendar choices, and live ZenQuotes daily quotes with author and source attribution. See [widget customization](WIDGET_CUSTOMIZATION.md) and [animation implementation and captures](WIDGET_ANIMATION.md).

All 63 iOS and 41 backend tests passed. The real generated idle preview and small Home Screen action/idle and Sleepy captures were inspected. Occasional brief missing widget frames remain in Simulator recordings; physical-device smoothness remains a beta check. App and widget signatures, shared App Group provisioning, all new idle/action fonts, room assets, and no non-exempt encryption declaration passed archive verification.

The matching backend deployment reached SUCCESS before the client upload. All 41 tests also passed inside the Linux image build. Live source hashes, configured integrations, authenticated saved-job access, animation-route Pro guard, unchanged wallet after rejection, and account/pet/job preservation were verified. No paid provider generation was performed during deployment validation, and temporary SSH access was revoked. See [backend evidence](live-validation/idle-loop-deployment.json).

Apple confirms **VALID**, **IN_BETA_TESTING**, membership in the existing **Internal Testing** group, and exact en-US What to Test readback. Archive/export/upload succeeded. Private release artifacts, source fingerprints, logs and verification records are preserved outside the workspace in `~/Library/Application Support/MyFurBaby/Releases/1.0-12`. Open the app after upgrading to rebuild saved widget frames, then add the missing idle animation through Animate my pet. No external beta review was submitted.

## Previous release: 1.0 (11)

**My Fur Baby 1.0 (11) is uploaded, processed and available in Internal Testing.**

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6820522244/testflight/ios).

Build 11 removes Running from widget moods and generation requests. Previously saved Running moods use Playful. Animate requests only missing licking and sleeping sequences, shows their current cost (up to 500 credits), and displays both an overall loading bar and per-animation progress driven by actual backend pipeline stages. Sleeping progress covers pose preparation/checking, background removal, final sleep/mouth checks, floating Zs, encoding, and saving. Progress reaches 100% after local frames are saved, and retries preserve completed animations. The archive also includes the previously prepared 20-second final-frame pause, updated branding/icon, and current shared screen changes.

All 50 iOS tests and 35 backend tests passed. Archive and upload succeeded. App and widget both report 1.0 (11), strict signatures and shared App Group provisioning passed, room assets and all animation/hold fonts are bundled, and the app declares no non-exempt encryption.

The matching backend was deployed first and verified against the uploaded source hashes. The progress-column migration, authenticated job-response contract, existing account/pet/job persistence, and unauthenticated rejection passed production checks without a provider generation or credit charge. All 35 tests also passed during the Linux image build. Temporary deployment verification access was revoked. See [backend evidence](live-validation/widget-progress-deployment.json).

Apple verification confirms **VALID**, **IN_BETA_TESTING**, build 11 in the existing **Internal Testing** group, and exact en-US What to Test readback. Release artifacts, source fingerprints, test results, logs, and verification records are preserved outside the workspace in `~/Library/Application Support/MyFurBaby/Releases/1.0-11`, with owner-only directory access. Continuous widget motion on physical devices remains a beta check.

## Previous release: 1.0 (10)

**My Fur Baby 1.0 (10) is uploaded, processed and available in Internal Testing.**

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6820522244/testflight/ios).

Build 10 retains all 45/60 frames of saved video animations in Home Screen widgets and targets 15 FPS while preserving the three/four-second clip duration. Earlier widgets sampled just four poses. New bundled cycle masks select one pose at a time, and exact source-frame indices prevent rounding from duplicating or skipping poses. Transparent frames are bounded to 256 pixels to leave memory headroom. The app explains when older four-pose artwork needs a video replacement for smoother movement. Opening the app after upgrading rebuilds its local cache from existing assets without generation or credit charges. Build 9's room background and transparency fixes remain included.

All 41 iOS tests passed, including complete 45/60-frame preparation, distinct source-pose retention, transparent canvas bounds, legacy metadata compatibility, and exclusive mask slots across minute boundaries. The final legacy-artwork message subsequently built successfully. Small and medium iOS 26.3 Simulator widgets rendered saved videos, and a native licking recording showed about 15 visible pose changes per second. This estimate is not a physical-device benchmark; continuous widget playback remains experimental.

Apple verification confirms **VALID**, **IN_BETA_TESTING**, build 10 in the existing **Internal Testing** group, and exact en-US What to Test readback. Archive and upload succeeded. Both signed bundles report 1.0 (10), strict signatures and shared App Group provisioning passed, both room assets and the new cycle fonts are bundled, and the app declares no non-exempt encryption. No external beta review was submitted.

Release artifacts, source fingerprints, logs, test records, notes, and Apple verification are preserved outside the workspace in `~/Library/Application Support/MyFurBaby/Releases/1.0-10`, with owner-only directory access. See [widget motion implementation and evidence](WIDGET_ANIMATION.md). No backend deployment or provider generation was performed for this client release.

## Previous release: 1.0 (9)

**My Fur Baby 1.0 (9) is uploaded, processed and available in Internal Testing.**

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6820522244/testflight/ios).

Build 9 fixes room backgrounds failing on the Home Screen when WidgetKit rejected their oversized images. The widget embeds cached room renditions bounded to 640 × 640 pixels. Motion frames preserve transparency instead of flattening the pet onto a lavender square, and paired masks prevent transparent poses from overlapping. Clear labels use adaptive text color for light and dark system surfaces. Opening the app after upgrading regenerates the versioned motion cache from existing artwork without generation or credit charges. Clear still uses the system-provided surface.

All 38 iOS tests passed. Actual iOS 26.3 Simulator Home Screen widgets were checked in small and medium sizes for Clear, Cozy, and Cyberpunk with motion on and off; extension logs confirmed successful archiving for both sizes. Compared with build 8, shipping source changes are limited to the shared artwork/background renderer, transparent motion-frame preparation, widget frame masks, and build number. Physical-device appearance and sustained automatic motion remain beta checks.

Apple verification confirms **VALID**, **IN_BETA_TESTING**, build 9 in the existing **Internal Testing** group, and exact en-US What to Test readback. The archive and upload succeeded. Both signed bundles report 1.0 (9), strict signatures and shared App Group provisioning passed, both room assets are bundled, and the app declares no non-exempt encryption. No external beta review was submitted.

Release artifacts, source fingerprints, upload logs, test records, notes, and Apple verification are preserved outside the workspace in `~/Library/Application Support/MyFurBaby/Releases/1.0-9`, with owner-only directory access. See [widget background fix and verification](GALLERY_AND_WIDGET_BACKGROUNDS.md). The newer video-animation backend was not deployed as part of this client release.

## Previous release: 1.0 (8)

**My Fur Baby 1.0 (8) is uploaded, processed and available in Internal Testing.**

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6820522244/testflight/ios).

Build 8 checks the saved Keychain account for the configured service before showing the first screen. Returning accounts bypass onboarding even if local pets or preferences are missing or old onboarding progress is incomplete. First-time accounts still see onboarding on their initial launch; creating the anonymous session during startup does not skip it in that run. Saved accounts are subsequently validated through the wallet endpoint without creating another account. Interrupted image recovery retains the original pet name. This uses the account saved on this device; cross-device account restoration remains unsupported.

All 37 local iOS tests passed, including missing local progress, stale onboarding stages, completion persistence, configured-service isolation, sample-mode isolation, and validating an existing session without another session-creation request. Client source comparison with build 7 confirmed only FurStore and the build number changed. The adventure gallery and widget backgrounds remain included.

Apple verification confirms **VALID**, **IN_BETA_TESTING**, build 8 in the existing **Internal Testing** group, and exact en-US What to Test readback. The archive and upload succeeded. App and widget both report 1.0 (8), strict signatures and shared App Group provisioning passed, both room assets are bundled, and the app declares no non-exempt encryption.

Release artifacts, source fingerprints, upload logs, testing notes, and verification records are preserved outside the workspace in `~/Library/Application Support/MyFurBaby/Releases/1.0-8`, with owner-only directory access. See [onboarding and launch routing](ONBOARDING.md). Automatic widget motion remains experimental; the newer video-animation backend was not deployed as part of this client release.

## Previous release: 1.0 (7)

**My Fur Baby 1.0 (7) is uploaded, processed and available in Internal Testing.**

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6820522244/testflight/ios).

Build 7 adds automatic local saving of completed and recovered photo adventures, with an in-app gallery below the generation controls. Memories reopen with their pet name, date, placement, Share, and Save to Photos actions. Recovery uses the saved job key to avoid duplicate gallery entries. Saved adventures remain viewable without an active Pro subscription.

Widget backgrounds now include Clear, a solid color from the native color picker, Cozy living room, and Cyberpunk bedroom. The selected background and picked color persist and synchronize with the widget extension. Both room assets are bundled in the signed app and widget. Names and captions use contrasting text and scene panels.

All 32 local iOS tests passed. Simulator visual checks covered the gallery, adventure detail, system share sheet, native color picker, and small/wide room previews. Physical-device widget appearance and Photos-library export remain beta checks. Automatic Home Screen widget motion remains experimental. The current local saved-animation playback changes are included in this client archive; the newer video-animation backend has not been deployed as part of this TestFlight upload.

Apple verification confirms **VALID**, **IN_BETA_TESTING**, build 7 in the existing **Internal Testing** group, and exact en-US What to Test readback. No external beta review was submitted. The archive and upload succeeded. Both signed bundles report 1.0 (7), strict signatures and shared App Group provisioning passed, and the app declares no non-exempt encryption.

Release artifacts, source fingerprints, upload logs, testing notes, and Apple verification records are preserved outside the workspace in `~/Library/Application Support/MyFurBaby/Releases/1.0-7`, with owner-only directory access. See [gallery/background behavior and screenshots](GALLERY_AND_WIDGET_BACKGROUNDS.md).

## Previous release: 1.0 (6)

**My Fur Baby 1.0 (6) is uploaded, processed and available for internal beta testing.**

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6820522244/testflight/ios).

Build 6 addresses the reported device regression: enabling motion displayed the illustrated
sample puppy and a gray name placeholder, while motion off displayed Sterling correctly.
It replaces shared-container artwork fonts with locally prepared PNG frames loaded as
UIImage views. The original bundled timer ligature mask still sequences the frames.
Opening the app after upgrading regenerates frame metadata. No image generation or
credits are needed to convert existing saved poses. Static fallback, Reduce Motion,
reduced luminance and Pro expiry remain supported.

All 26 iOS tests pass. The isolated Simulator snapshot contains four image frames for
each mood with no runtime artwork-font metadata. Both signed bundles report 1.0 (6),
the timer mask is bundled, and the app's non-exempt-encryption declaration remains false.
Apple verification confirms VALID processing, IN_BETA_TESTING, build 6 in the Internal Testing group, and exact en-US What to Test readback. The archive and upload succeeded. Continuous Home Screen animation remains unverified:
Simulator gallery interaction did not complete and no physical iPhone was connected.
See [device test instructions](WIDGET_ANIMATION.md).

Release artifacts and verification records are preserved outside the workspace in
`~/Library/Application Support/MyFurBaby/Releases/1.0-6`, with owner-only access.

## Previous release: 1.0 (5)

Build 5 implemented generated bitmap artwork fonts with Bryce Bostwick's original
bundled mask. Apple processed it and made it available in Internal Testing. Its 24
local tests passed, but a user device showed the redacted placeholder when enabling
motion. Shared-container font access by the system renderer is the likely cause,
consistent with the [Apple forum report](https://developer.apple.com/forums/thread/671476).
Build 6 removes these runtime font references from the widget.

## Previous release: 1.0 (4)

**My Fur Baby 1.0 (4) is uploaded, processed and available for internal beta testing.**

[Open TestFlight in App Store Connect](https://appstoreconnect.apple.com/apps/6820522244/testflight/ios).

Build 4 fixes onboarding stopping after a single connection timeout. It retries interrupted requests using the same saved creation key and job, allows longer image responses, and keeps recovery available across launches. Extended outages show a friendly inline recovery message instead of a raw timeout alert. Returning to the foreground resumes an unfinished creation. Messages scroll while waiting, including “Building toe beans…” and “Filling them with love…”, with a gentle fade for Reduce Motion and a stable VoiceOver progress label.

The reported creation completed on the server despite the client timeout. The release does not submit an extra creation or debit credits when recovering that saved job.

Apple API verification:

- Upload succeeded; export completed.
- Build processing state: VALID.
- Internal build state: IN_BETA_TESTING.
- External build state: READY_FOR_BETA_SUBMISSION; no external review was submitted.
- Internal Testing group: automatic build access; build 4 was read back in the group's build list.
- What to Test: saved in en-US and read back to verify it matches `TestFlight-WhatToTest.txt`.
- App encryption declaration: no non-exempt encryption.

The device archive completed. App and widget passed strict signature checks, both report 1.0 (4), and both provisioning profiles contain `group.com.gregadams.myfurbaby.shared`. Both onboarding MP4s were verified in the archived app.

All 18 iOS tests passed, including seven network regression tests covering timeout recovery, lost submission responses, same-key retries, relaunch recovery, server failures, continued processing and terminal errors. A connected Simulator walkthrough injected a sustained outage, verified rolling messages and inline recovery with no alert, and recovered the original pet at the reveal. The mock server recorded exactly one creation submission across both attempts. Verification made no provider calls or purchases.

The existing backend deployment remains unchanged at `https://myfurbaby-api-production.up.railway.app`. Deployment 0d764673-fc93-4f3b-9e05-7009dce5fba7 reached SUCCESS and passed 27 backend tests. Build 3 introduced the eight-stage onboarding, demo videos, gender-aware questions, free first creation, reveal and name confirmation, and personalized paywall; all remain in build 4.

The signed archive, upload logs, notes verification and release records are preserved outside the workspace in `~/Library/Application Support/MyFurBaby/Releases/1.0-4`, inside an owner-only directory. API credentials remain outside the project. UI proof is in `docs/screenshots/onboarding/`.

Known limitations: onboarding clips are demo previews; automatic Home Screen widget motion is experimental; cross-device account restoration is not supported; real Sandbox purchase and notification delivery remain unverified. Hosting currently uses Railway trial credits. No tester invitations were sent, and no App Store release was submitted.

Previous builds 1.0 (2) and 1.0 (3) remain available in TestFlight.
