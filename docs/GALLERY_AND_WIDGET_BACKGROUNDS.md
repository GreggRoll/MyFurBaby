# Adventure gallery and widget backgrounds

Completed adventures are saved automatically on this device as full images plus 480-pixel thumbnails, with pet name, placement, and creation date. The gallery sits below generation controls in Adventures and remains available without an active Pro subscription. Tap a thumbnail to reopen, share, or save to Photos. Pending photo jobs retain their original pet and placement for recovery; the saved job key prevents duplicates. Adventures are separated between sample and connected modes. Images from before this update cannot be reconstructed from the former transient screen state, but unfinished jobs recovered after the update are added.

Widgets offer Clear, Solid color (native color picker without opacity), Cozy living room, and Cyberpunk bedroom. Selections and RGB color persist across launches, synchronize through the App Group, and reload WidgetKit timelines. Both preview sizes use the same background renderer as the extension; labels choose contrasting text and translucent panels for room scenes. Clear supplies no custom background; iOS controls the final widget surface.

Room artwork was generated with the built-in image generation tool. Saved project assets:
- `Resources/Assets.xcassets/widget-cozy-living-room.imageset/widget-cozy-living-room.png`
- `Resources/Assets.xcassets/widget-cyberpunk-bedroom.imageset/widget-cyberpunk-bedroom.png`

## Verification

### October 8 follow-up: Home Screen rendering fix (build 9)

Reproduced a room selection leaving the previous black Clear widget on screen. The extension log reported `WidgetArchiver.ArchivingError.imageTooLarge`: the 1,254 × 1,254 room image exceeded the small widget's archive limit (1,572,516 pixels versus 1,069,415.6 allowed). WidgetKit rejected the new timeline instead of replacing the previous widget. Room images now use cached renditions no larger than 640 × 640, embedded as UIImages in the view archive; original project assets remain intact.

Motion frame preparation also used an opaque lavender canvas. It now preserves alpha, and the versioned cache regenerates previously flattened frames when the app next publishes its widget. Paired timer masks expose exactly one pose at a time so transparent poses cannot stack. Clear text uses the system's adaptive primary color to stay readable on dark surfaces. Clear still supplies no custom background; iOS determines its final surface and transparency.

The final app/widget build and all 38 iOS tests passed. Regression checks cover bounded room dimensions, transparent frame corners with visible artwork, all eight mutually exclusive mask slots using the actual font, and Clear text contrast in light/dark environments. Actual iOS 26.3 Simulator Home Screen widgets were checked in small and medium sizes for Clear, Cozy, and Cyberpunk with motion enabled and disabled, using the local sample pet. Extension logs confirmed successful archiving for both sizes after the fix. Screenshots are in [widget-background-fix](screenshots/widget-background-fix/). No live generation or purchases were used. Physical-device appearance and sustained animation remain unverified. Build 1.0 (9) is uploaded, processed as VALID, and available in Internal Testing, with its What to Test notes read back successfully.

### Original build 7 verification

All 32 iOS tests passed on the iOS 26.3 Simulator, covering adventure image and thumbnail persistence across launches, invalid image rejection, recovery-key deduplication, original pet and placement recovery, backward-compatible decoding, picked-color persistence, and publication to the widget snapshot. The final app and widget extension build succeeded after the color picker layout adjustment.

Simulator visual checks covered Clear and both room scenes in small and wide previews, all four selectable backgrounds, the native color picker opening, the gallery below generation controls, reopening a memory, and the system share sheet. Gallery screenshots use two existing local photo fixtures in an isolated QA storage suite; this walkthrough made no live AI generation requests. Photos-library export and physical-device widget appearance were not exercised. Build 1.0 (7) is uploaded, processed as VALID, and available in the existing Internal Testing group. The en-US What to Test notes were published and read back successfully.

- [Cozy widget previews](screenshots/gallery-backgrounds/widget-cozy.jpg)
- [Cyberpunk widget previews](screenshots/gallery-backgrounds/widget-cyberpunk.jpg)
- [Native color picker](screenshots/gallery-backgrounds/color-picker.jpg)
- [Adventure gallery](screenshots/gallery-backgrounds/adventure-gallery.jpg)
- [Adventure detail](screenshots/gallery-backgrounds/adventure-detail.jpg)

## Generation prompts

### Cozy living room

Use case: stylized-concept. Asset type: square background artwork for a small iOS pet widget, also cropped to a wide widget. Primary request: a cozy living room. Style: polished soft plush-cartoon 3D illustration, warm and welcoming, rounded furnishings, soft cream and lavender sofa in the back, warm lamp, gentle daylight, simple uncluttered composition. Composition: straight-on interior view; furniture along the back wall in the upper half; a broad empty softly textured rug and floor in the lower half and center where a separate pet will be overlaid. Keep the focal center open, enough floor for a pet to sit. No people, no pets, no animals, no lettering, no watermark. Full bleed square scene, no border.

### Cyberpunk bedroom

Use case: stylized-concept. Asset type: square background artwork for a small iOS pet widget, also cropped to a wide widget. Primary request: a cyberpunk bedroom. Style: polished soft plush-cartoon 3D illustration with rounded furnishings, a futuristic bed along the back wall, violet and cyan neon accent lights, night city window, cozy sci-fi atmosphere. Composition: straight-on room view; bed and furniture along the back wall in upper half, broad empty floor and soft rug in center and lower half where a separate pet will be overlaid. Keep central focal area open and readable at tiny sizes. No people, no pets, no animals, no lettering, no screens with text, no watermark. Full bleed square scene, no border.
