# Widget animation

## Playful naming and playback handoffs — local update, October 9, 2026

The action is now named `playful` throughout the app, widget, generation tools and backend. New prompts choose a short action appropriate to the animal’s species, anatomy and personality. Licking is an optional suggestion only for animals where it makes sense. Existing saved artwork keys, frame filenames, paid jobs and backend caches migrate or remain readable; they do not trigger regeneration or another charge. This is a local source update and requires a client release and matching backend deployment.

Widget masks now overlap adjacent poses by at most one 60 Hz display refresh (16.7 ms). The previous exact intersection left no tolerance for independently scheduled timer updates and could briefly hide all poses. This trades a short overlap of two adjacent transparent poses for tolerance at the handoff. Timeline entry references align to a common whole-cycle clock so hourly refreshes preserve phase. The 15 FPS target, full source frames, 192-pixel widget canvas, idle interval and static accessibility fallbacks remain. The PNG cache version is 8.

App previews prepare and retain complete decoded action/idle sequences off the main thread, bounded to 384 pixels. The per-frame view only indexes those arrays, avoiding PNG reads and decode work when the 32 MiB shared cache evicts frames. Auto mood selection updates once a minute outside the frame loop, and sleeping samples breathe continuously.

Regression checks cover old pet data, cache and paid-job reuse, database migration, decoded preview frames, phase continuity and nonempty handoffs using the actual bundled mask fonts at eight samples per animation slot. All 66 iOS and 45 backend tests passed. The updated saved pet and 75 awake/60 sleeping frames were published to the Simulator widget. Native captures showed corruption across the whole Simulator screen, including stale app and Home Screen layers, so they were excluded from smoothness validation. Timer rendering remains controlled by the system; physical-device playback still needs verification.

## Action and idle loops — TestFlight 1.0 (12)

New playback videos use `fal-ai/pixverse/v6/transition`, passing the same uploaded reference as `first_image_url` and `end_image_url`. Sleeping playback uses its validated reclining sleeping reference at both endpoints. The internal one-way settling video still prepares that seed through image-to-video; forcing it back to an upright reference would prevent a sleeping end pose.

Awake playback now runs the action once, then repeats a new two-second idle clip five times for exactly ten seconds before restarting the action. Playful therefore has a thirteen-second cycle. The idle prompt asks for cute, relaxed breathing, a blink, tiny ear/tail twitches and a small weight shift. Sleeping/snoring loops continuously, with no awake idle or still hold. Existing videos remain saved; endpoint guidance applies to newly generated videos. Pets missing idle repeat their action until the new clip is prepared.

The client requests only missing idle/playful/sleep clips. Each costs the existing 1,500 tokens; idle adds one generation to the initial set (4,500 total), and saved replay is free. Partial results persist, and server retry/idempotency rules also cover idle.

Widget cache version 7 uses bundled `FurLoop12/13/14` action masks and `FurIdle12/13/14` idle pulse masks for complete awake cycles. Ten seconds of idle has 150 timing slots, but uses thirty 192-pixel PNG layers: idle pulse masks expose each pose five times. A playful cycle has 75 layers and 75 distinct images (10.55 MiB decoded image data before archive/rendering overhead); a four-second action has 90 layers and at most 90 distinct images (12.66 MiB). Sleeping retains sixty images/layers. The 256-pixel attempt exceeded WidgetKit's timeline archive limit with the added idle images; prepared widget images are now smaller while full-quality video assets remain saved. Old hold metadata/fonts remain decodable. Awake elapsed-seconds cycles require iOS 18; Reduce Motion, dimmed displays and unavailable frames retain the still fallback.

Validation: 41 backend tests and 63 iOS tests passed, including identical endpoint requests, thirty-frame idle generation/cache, HTTP charge/recovery, five-loop image reuse, and exactly one visible frame across action/idle, minute and hour boundaries. A real PixVerse transition/VEED idle generation produced thirty transparent 512-pixel frames at 15 FPS. The start and end poses match the reference visually; smoothness on a physical device remains unverified. [Ten-second idle preview](live-validation/idle-loop/pet/idle-preview.mp4).

The small Home Screen widget rendered the real generated pet after reducing the prepared images to 192 pixels. Native captures show the thirteen-second action/idle cycle repeating and Sleepy staying asleep with continuous movement. The awake recording contains one briefly missing pet frame among 380 samples at 15 FPS; the sleep recording also shows a brief missing frame. Timer-mask widget playback remains experimental, so these captures do not establish flicker-free physical-device playback. [Captures and validation](screenshots/widget-idle-loop/).

The matching backend is deployed, and these client changes are available in TestFlight 1.0 (12) Internal Testing. See [release verification](TESTFLIGHT_RELEASE.md).

## Final-frame pause — TestFlight 1.0 (11)

Animations now finish their clip, hold the final frame for 20 seconds, then restart. Playful videos have a 23-second cycle (3 seconds of movement plus 20 seconds held); sleeping/running videos have a 24-second cycle. The in-app preview follows the same rule and starts at the beginning when it appears or the mood changes. Procedural samples and older four-pose sheets use four seconds of movement plus the hold.

New optional `hold` metadata preserves decoding of build 10 and older snapshots. Cache version 5 rebuilds the prepared frames locally. The widget adds one held-image layer instead of duplicating the final frame 300 times. Images stay transparent and bounded to 256 pixels; saved video movement still targets 15 FPS.

The new mask fonts operate on a single total-seconds field from iOS 18's system DateOffset formatter. The classic timer separates minute/second fields and could not reliably shape the whole elapsed clock through the new mask. Total seconds avoid that boundary. Bundled `FurLoop22/23/24` and `FurRest22/23/24` fonts use digit-pair ligatures, with one set exposing movement slots and the other exposing the 20-second hold. Five numeric digits cover over 27 hours; timeline entries normally realign their reference every hour. iOS 17 uses a still-pose fallback for the new hold metadata. Existing snapshot metadata without a hold remains compatible with the older masks.

All 43 iOS tests passed, covering exact last-frame holding across multiple app loops, one visible widget pose at every slot including hold/restart and minute/hour boundaries, legacy metadata, full 45/60-frame retention, and transparent canvas bounds. Small sleeping and medium playful Home Screen widgets were verified with native 50-second captures. The playful capture showed movement, a roughly 20-second still interval, then restarting. Home Screen verification is recorded in [widget-hold-last-frame](screenshots/widget-hold-last-frame/). These changes are included in TestFlight build 11. Physical-device behavior remains a beta check.

## Smoother saved-video playback — TestFlight 1.0 (10)

Build 9's widget reduced every saved clip to four poses and replayed them at four pose changes per second. Build 10’s renderer keeps all 45 frames of a three-second playful video and all 60 frames of a four-second running/sleeping video, at a target of 15 FPS and their original duration. Procedural samples also use 60 frames over four seconds. Old four-cell sheets retain their four-pose cadence: they contain no intermediate movement.

Two new original, bundled mask fonts expose one second out of a three/four-second cycle. Intersecting each frame's mask window with the next frame's previous window selects one 1/15-second slot, including across minute boundaries. The original two-second font remains for legacy snapshots. No artwork fonts are registered from shared storage. Transparent PNGs are bounded to 256 pixels per side; 60 decoded frames occupy 15 MiB before renderer overhead. Cache version 4 rebuilds from existing assets without provider calls or app credits. Clip FPS is capped at 15 and mask periods at two to four seconds; other clip durations are fitted to those periods.

All 41 iOS tests passed, including complete 60-frame preparation, retention of all 45 distinct source poses, alpha/canvas bounds, legacy decoding, invalid timing rejection, and exclusive 15-FPS mask slots using the actual bundled fonts. Small and medium widgets rendered existing generated clips in Simulator without archive rejection. Native Simulator captures show continuous playback with the new three/four-second masks; the playful capture shows about 15 visible pose changes per second. Capture-based estimates are not a physical-device performance guarantee. The app explains when an older four-pose animation needs a video replacement for smoother motion. Evidence is in [widget-smooth-motion](screenshots/widget-smooth-motion/). Continuous playback still depends on undocumented timer rendering and physical-device smoothness is not established. Build 1.0 (10) is available in TestFlight Internal Testing. Open the app once after upgrading to rebuild saved widget frames.

## Historical build 1.0 (6)

Assets use continuous PixVerse V6 video, VEED background removal, and fixed-canvas RGBA sequences at 15 FPS. The app plays all frames. See [video pipeline](VIDEO_ANIMATION.md). The rest of this section describes released build 6.

Build 6 fixes the motion rendering path reported on iPhone in build 5: enabling motion
replaced the actual pet and name with the illustrated sample and a gray redaction bar.
Motion off displayed Sterling correctly. This is consistent with a failed WidgetKit view
archive rather than missing pet data.

The likely cause is runtime artwork fonts registered from the App Group. The
[Apple Developer Forums report](https://developer.apple.com/forums/thread/671476)
describes this exact placeholder symptom when the system widget renderer cannot read
shared-container fonts, even though Simulator and CoreText tests succeed. No device logs
were available to prove that diagnosis on the user's phone.

The app now renders four opaque 384-pixel PNG frames per available mood, saves them
atomically in the App Group, and embeds loaded UIImage frames in the widget view.
The widget no longer registers or references dynamically generated fonts. Build 5 font
metadata remains decodable for upgrades, but is ignored; opening the app regenerates
image metadata. Missing frames, Reduce Motion, and reduced luminance use a still pose.

Eight image layers, offset by 0.25 seconds, use the original bundled ligature timer mask
from [Bryce Bostwick's WidgetAnimation](https://github.com/brycebostwick/WidgetAnimation),
commit `a3b1a424d22387bfcbe54f7ff3acb7335d4e418c`. Two stacks sequence four saved poses across
the mask's two-second period. Opaque lavender backgrounds cover earlier poses. The
mask is bundled as `FurTimerMask.otf` with its `Custom-Regular` PostScript name preserved.
MIT attribution is in `THIRD_PARTY_NOTICES.md` and both bundles. The unused binary
framework from the demo is not included.

No provider calls or image credits are needed to prepare or replay saved frames.
Preparing missing four-frame animation sheets still uses the existing up-to-500-credit
flow. Pro expiry remains an explicit timeline entry.

## Validation

The iOS test suite checks image preparation, distinct poses within each mood, stable
cache reuse, complete image loading, safe filename handling, missing-frame fallback,
legacy snapshot decoding, and the bundled mask's alternating seconds-pair ligatures.
Historical bitmap-font tests remain, but do not establish device widget compatibility.
The shared Simulator snapshot contains four image frames for each mood and no runtime
artwork-font metadata. The Release archive's build number, encryption declaration and
app/widget signatures are verified before upload.

Continuous Home Screen animation has not been established. Motion is now enabled
automatically for eligible widgets: timer text rendering does not provide a documented guarantee of
arbitrary continuous widget motion. No physical iPhone is connected for local testing.

## TestFlight device checks

1. Install the current client and open the app to regenerate saved widget frames.
2. With Pro and a saved pet, motion is enabled automatically. Confirm the actual
   pet and its name appear, without the sample placeholder or gray bar.
3. Select Playful and watch the small and medium widgets for at least 30 seconds;
   repeat with Sleepy. Report whether the poses loop without touching the widget.
4. Leave and return to the Home Screen, lock/unlock, terminate the app and revisit.
5. Check Reduce Motion, Low Power Mode, tinted widgets and multiple instances.
6. If the placeholder persists, reopen the app, then remove and re-add the widget.
   Record the iPhone model, iOS version, widget size and mood.
7. Before promising motion as a production feature, verify sustained looping on
   physical devices and measure energy use.

The current client removes the automatic-motion toggle, beta explanation, and motion setup messages from Widgets. The app no longer reads the old opt-in setting and always prepares and publishes motion frames for a Pro pet. The widget always uses the motion renderer, including when loading a legacy snapshot with the old flag off. The renderer still falls back to a still pose for missing frames, Reduce Motion, dimmed displays, and unsupported elapsed-seconds rendering. Existing saved animations are reused without paid generation.
