# Live fal.ai animation verification — October 8, 2026

Source: the existing purple puppy cutout at `../in-app-pet.png`. Its exact bytes are preserved as `pet/original.png`; SHA-256 is recorded in `verification.json`.

| Animation | Duration | Frames | Canvas | FPS |
| --- | ---: | ---: | --- | ---: |
| Lick | 3 seconds | 45 | 512×512 RGBA | 15 |
| Run | 4 seconds | 60 | 512×512 RGBA | 15 |
| Sleep | 4 seconds | 60 | 512×512 RGBA | 15 |

The supplied key initially received HTTP 403. After account credits were added, uploads and all model calls succeeded. The key is kept only in the ignored local backend environment file, excluded from Docker context and app source.

PixVerse V6 created continuous clips and VEED removed their backgrounds with animal mode and VP9 output. FFmpeg extracted every frame with explicit libvpx decoding. Validation confirms consecutive filenames, expected counts, equal canvas dimensions, alpha and visible foreground. No bounding-box cropping or per-frame recentering was used.

Visual observations from eight evenly spaced frames per animation:

- Lick preserves purple fur, pink collar and tail. The animal leans forward and moves its tongue, then returns to a sitting pose.
- Run preserves the same design and remains visible while its body, paws and ears move through the canvas. It returns to sitting.
- The initial sleep clip included settling and intermittent eye opening. Its final asleep RGBA frame became `sleep-reference.png`; a second continuous clip supplies the final 60-frame sequence. Sampled final frames show closed eyes and subtle torso/ear motion with minimal repositioning.

First and last frames are not identical. Seamless looping has not been certified, and identity/edge quality across other animals remains untested. Running and licking include transitions to and from their action, rather than a repeated gait or repeated tongue cycle throughout. This is actual generated output, not a guarantee for every pet.

`pet/preview.html` plays the exact PNG sequences and supports pause and individual frame scrubbing. Each behavior also has `animation.json`, `transparent-pet.webm` and `contact-sheet.png`. Serve it locally:

```sh
python3 -m http.server 8792 --bind 127.0.0.1 --directory docs/live-validation/fal-animations/pet
```

Open `http://127.0.0.1:8792/preview.html`. The preview was inspected in the Codex browser with all 165 frames loaded.

The final source passed 31 backend tests and 28 iOS Simulator tests. Backend tests include real VP9-alpha extraction and sleeping-seed retry behavior. The Linux Docker image includes FFmpeg and runs the backend tests during its build.

These assets and integration changes are local. Railway and TestFlight have not been updated. The app plays the entire 15 FPS sequence; the existing widget workaround samples four poses per mood and does not establish continuous physical-device playback.

## Subsequent sleeping requirement

The user accepted this test but specified that future sleeping generation must use the supplied animal lying on its back or side, visually snoring loudly, with Zzzs coming from its mouth. Sleeping behavior revision 2 implements reclining-pose checks, stronger snore motion prompts, mouth tracking and post-segmentation vector letters. Audio remains disabled by explicit user choice. The seated video and preview in this folder have not been regenerated and do not demonstrate the new reclining behavior. See `snore-revision-check.json` for the live vision check of this existing fixture, and `docs/VIDEO_ANIMATION.md` for the current pipeline.
