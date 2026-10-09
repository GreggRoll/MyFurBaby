# Video animation pipeline

The local source uses fal.ai's [PixVerse V6 image-to-video](https://fal.ai/models/fal-ai/pixverse/v6/image-to-video/api), followed by [VEED video background removal](https://fal.ai/models/veed/video-background-removal/api). Pet creation and photo adventures continue to use the existing image service.

| Animation | Seconds | FPS | RGBA frames |
| --- | ---: | ---: | ---: |
| Playful | 3 | 15 | 45 |
| Running | 4 | 15 | 60 |
| Sleeping | 4 | 15 | 60 |

The canonical PNG is saved byte-for-byte as `original.png`. Only the temporary video reference is flattened on white. Its silhouette is never trimmed. PixVerse preserves identity and style, keeps the entire animal visible and uses a fixed camera and scale. Audio, multiple clips and prompt optimization are disabled. VEED uses `subject_is_person: false`, refined edges, and `output_codec: "vp9"`.

Sleeping now requires the supplied animal to lie **on its back with belly up, or fully on its side**, with closed eyes and visible face/mouth. A continuous settling clip supplies the asleep starting frame. A fal.ai [Moondream pose check](https://fal.ai/models/fal-ai/moondream3-preview/query/api) rejects upright sitting/standing and ambiguous poses before saving the seed. A second continuous clip shows pronounced visual snoring: chest/belly inflation and deflation, relaxed jaw and cheek vibration, and gentle mouth opening/closing. Audio stays disabled, as requested for widgets.

After VEED removes the background, [Moondream pointing](https://fal.ai/models/fal-ai/moondream3-preview/point/api) locates the mouth in the first, middle and last frames. Pose checks also cover those three frames. Mouth positions are interpolated only to place the effects; the animal and fixed canvas are never shifted. Three vector Zs emerge from the mouth, drift upward/outward, grow and fade on a two-second cycle. They are composited into each RGBA PNG **after segmentation**, then the transparent WebM is rebuilt from those final frames so both deliverables contain the same letters. This avoids relying on model-generated spelling or on segmentation preserving separate text.

Sleeping behavior revision 2 uses a separate, source-hash-bound seed cache and requires effect metadata. Old seated-dozing seeds and sequences are not accepted as the current pipeline output. Existing test artwork stays available as historical evidence; existing app-saved animations are not automatically regenerated. New generations use the reclining/snoring requirements. The vision checks are a guard against the observed regression, not a guarantee of anatomy, identity or motion quality in every frame. Failed checks fail the job and return app credits instead of caching an upright sleeper.

The seed is reused after later-stage failures. The original PNG remains unchanged. Sleeping needs two video/segmentation calls the first time, plus pose/mouth analysis; its app charge stays 250 credits. Continuous seamless looping still needs visual review.

FFmpeg explicitly decodes with `libvpx-vp9`. Source alpha is checked before padding. One constant scale-to-fit and transparent padding transform applies to the entire clip. Every extracted PNG must have the same 512×512 RGBA canvas, visible foreground, some transparency, consecutive filenames and the complete expected frame count. No frame is independently cropped, recentered or resized around the animal. Camera stabilization is not applied automatically because it could remove intended movement.

## Configuration and storage

Set `FAL_KEY` in the private, ignored `backend/.env` or hosting runtime variables. The iOS app contains only the service URL and its own account session. Docker includes FFmpeg; local development needs FFmpeg with `libvpx-vp9`. `FFMPEG_PATH` optionally selects a binary.

```text
data/animations/PET_ID/
  original.png
  sleep-reference-v2.png
  sleep-reference-v2.png.json
  playful/
    animation.json
    transparent-pet.webm
    frame_0001.png ... frame_0045.png
  run/
    animation.json
    transparent-pet.webm
    frame_0001.png ... frame_0060.png
  sleep/
    animation.json
    transparent-pet.webm
    frame_0001.png ... frame_0060.png
```

Metadata records the fixed canvas, FPS, duration, ordered filenames, provider models and request IDs. `loopSeamVerified` initially remains false: prompts do not guarantee exact appearance, anchoring or a seamless return to the start. Review output before promising quality. Videos and RGBA frames consume considerably more space than old sheets; measure storage before expanding the hosted beta.

To animate an existing PNG, run from `backend`:

```sh
node --env-file-if-exists=.env generate-animations.js INPUT.png OUTPUT_DIRECTORY
```

Append `playful`, `run` or `sleep` to generate one animation. Valid completed sequences are reused. This CLI calls fal.ai directly and incurs provider charges without changing the app credit ledger.

## API and playback

Authenticated `POST /v1/pets/PET_ID/animations` with `{ "kind": "playful" }` returns a job receipt immediately. Poll authenticated `GET /v1/jobs/JOB_ID`. Completed results contain animation metadata, `framesBase64` and the current wallet. Ownership and Pro access are enforced. Concurrent retries share the pending reservation; validated completed animations reuse their receipt without a new charge.

Each animation costs 250 app credits. The app requests missing animations sequentially and saves each before requesting the next. Failure refunds that reservation. Relaunching and tapping Animate again retrieves pending or completed jobs for the same pet and kind. Provider failures are sanitized. Jobs remain in-process: restarts refund pending reservations and can lose a provider call already billed. Avoid deployment during active jobs; durable workers remain future work.

The widget currently offers Auto, Playful, and Sleepy. Running is temporarily hidden; previously saved Running choices fall back to Playful, and saved running sequences remain decodable. Animate requests only missing idle, playful and sleeping sequences, costing 1,500 tokens each and up to 4,500 for all three. New playful prompts select an action suited to the animal; licking is optional when appropriate.

The Animate button shows overall progress based on completed pipeline stages, with a separate loading bar and current stage for each requested animation. Job polling returns optional `progress: { kind, stage, completedStages, totalStages }`, saved in the job ledger and visible only to its owner. Playful has five stages: reference preparation, video generation, background removal, frame extraction/validation, and saving. Sleeping has twelve, adding sleeping-pose generation, segmentation, extraction and verification, final pose/mouth checks, floating Zs, and video re-encoding. A cached sleeping seed skips its completed preparation stages. Percentages count stages, not elapsed time; they advance when the pipeline reaches the next stage. The app marks 100% only after its local frames are saved. Retrying requests only missing animations. Older backends without stage data remain compatible but require this backend update for intermediate progress.

The app stores a descriptor and every RGBA frame, then plays by elapsed time at the recorded FPS. Generated movement receives no extra synthetic rotation or scale. Inactive previews and Reduce Motion show a still frame. The decoded-image cache is capped at 32 MiB. Existing pets, snapshots and four-cell sheets remain compatible.

Released build 9's widget displays four uniformly sampled transparent poses per mood. Build 10’s renderer keeps the complete 45/60-frame sequences at a target of 15 FPS and their three/four-second duration, using bundled cycle masks and 256-pixel transparent renditions. Legacy two-by-two sheets still have only four poses. Continuous motion and smoothness on physical devices remain unverified. The newer local source adds a 20-second final-frame hold before restarting, in the app and iOS 18+ widgets. See [widget renderer details](WIDGET_ANIMATION.md). The legacy `/poses` route samples missing two-by-two sheets from fal video output.

## Verification

Sleep retry fix (October 8, 2026): three recorded production vision checks returned `{"pose":"lying on its back belly up","eyes_closed":true,"unknown":false}`. The strict enum validator rejected these descriptions even though the animal met the sleeping requirements. It now normalizes a finite set of unambiguous reclining descriptions to `back` or `side`, while continuing to reject upright, open-eye, negated, and ambiguous results. Regression tests use the actual response wording throughout the sleep pipeline. Railway deployment `67db3b47-65e8-464a-abee-c130515a103f` is successful; live verification accepts all three recorded responses and still rejects upright poses. All 35 backend tests, 46 iOS tests, and the production container checks passed. No new paid animation was generated in this verification. Existing failed reservations were refunded; retrying creates a new reservation and skips already-saved playful/running animations. See [sanitized evidence](live-validation/sleep-validator-fix.json).

Backend tests cover model parameters, original-byte preservation, cache reuse, unsafe downloads, account privacy, pending retry deduplication and refunds. Sleeping tests reject upright/open-eye/ambiguous poses, validate mouth coordinates, check seed reuse, and verify that animated Zs add visible alpha pixels while preserving animal pixels and fixed dimensions. A real FFmpeg VP9-alpha test moves a visible shape between two frames and checks that its positions differ while the canvas stays fixed. Opaque and incomplete outputs are rejected.

iOS tests cover RGBA byte preservation, fixed dimensions, frame timing and wraparound, persisted metadata, invalid canvas rejection and widget sampling. Live outputs and visual observations are under `docs/live-validation/fal-animations`.

The client is available in TestFlight 1.0 (10). The matching Railway backend was deployed on October 8, 2026 (deployment `86d6f5d8-da33-4437-a1cf-41f489e2cd23`). Live health confirms animation, image and purchase integrations are configured. An authenticated route probe now reaches the Pro access check instead of returning 404; the account, wallet and previous artwork survived deployment. All 34 backend tests and the production-style container smoke test passed, including VP9 extraction, the animation route and persistence. No paid video was generated during this deployment verification. See [sanitized deployment evidence](live-validation/animation-route-deployment.json).
