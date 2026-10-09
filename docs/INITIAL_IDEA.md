> Historical brainstorming notes. Superseded by PROJECT_PLAN.md and the $4.99/$50 credit model.

# My Fur Baby — product and development plan

Updated: October 7, 2026. Status: planning complete; automatic widget animation remains unproven on current devices. No app implementation has started.

## Product promise and confirmed requirements

Create a custom animal, give it a name, and have it live on your iPhone Home Screen. Take it into your own photos when you want a new adventure.

Confirmed by Greg:

- Two Home Screen sizes: a small square and a medium wide rectangle.
- Automatic animation while the widget is visible is essential. Tap-triggered reactions alone do not meet the requirement.
- Signature behaviors: a playful action suited to each animal and sleeping on its back with visible snoring.
- Animal choices: dog, cat, chinchilla, rhinoceros, and an original fantasy animal called a gigglegoop.
- Colors: red, purple, green, yellow, and ombre. Accessories include a studded collar, top hat, and monocle.
- OpenAI `gpt-image-2` for pet artwork and photo editing.
- Proposed subscription prices: $1.99/month and $20/year. Image allowances and credit packs need cost validation.

Recommended starting art direction: a plush cartoon pet with a simple silhouette, expressive face, and readable accessories. This is a design recommendation, not a confirmed preference. The square widget emphasizes the face; the wide widget shows more of the body and habitat. One pet is sufficient for the first release.

## 1. Prove automatic widget animation first

This is the dependency for the entire product. Build a small experiment with prepared dog artwork before adding accounts, AI generation, or payments.

Apple documents widget update animations lasting at most two seconds. Widget views are archived and rendered by the system; their ordinary view code is not continuously running on the Home Screen. Frequent timeline reloads are subject to budgets. These constraints do not establish a supported way to run arbitrary looping pet animation. [Apple animation documentation](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities), [WidgetKit foundations](https://developer.apple.com/videos/play/wwdc2026/277/)

There is a relevant historical public-API proof of concept: Bryce Bostwick's WidgetAnimation demonstrates a looping widget animation. Its issue tracker contains a report that it stopped working on iOS 26.2. That report is a compatibility warning, not a result we have independently verified. [Original project](https://github.com/brycebostwick/WidgetAnimation), [Compatibility report](https://github.com/brycebostwick/WidgetAnimation/issues/3)

Investigation sequence:

1. Audit the original demonstration and timer/font-based techniques, including source, licenses, and SDK dependencies. Identify what is documented, what relies on undocumented behavior, and what uses private APIs.
2. Test an automatic tongue movement and a sleeping breathing/snoring loop in both widget sizes on real iPhones running the current shipping OS and any older OS we propose to support.
3. Run a release build without a debugger or WidgetKit developer mode, with the app backgrounded and terminated. A Simulator demo is useful but does not pass this milestone.
4. Test repeated Home Screen visits, locking/unlocking, rebooting, adding/removing widgets, multiple widget instances, offline use, Low Power Mode, Reduce Motion, and tinted appearance. Record where motion pauses and whether it resumes automatically.
5. Measure memory, CPU, and energy behavior. Compare the animated widget with an equivalent static widget. Do not infer zero battery impact from a demonstration.
6. Record videos and a device/OS compatibility matrix. Investigate App Review acceptance early if the method relies on unusual use of otherwise public APIs; a technical demo or TestFlight build does not guarantee production approval.

Proposed acceptance target: clearly recognizable playful and snoring motions repeat automatically through a 30-minute observation in each size, with no taps, no active main app, and no per-frame network calls. Resume automatically after leaving and returning to the Home Screen. Accessibility and power-saving modes may intentionally show a still pose and must be disclosed accurately.

Shipping requires an API implementation we can justify, acceptable resource use, and current-device evidence. Apple requires public APIs used for their intended purposes. A method that only works through private APIs does not pass the shipping decision. [App Review guideline 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

If this investigation cannot satisfy automatic motion, document the exact limitation and revisit the product with Greg. Do not quietly substitute tap-only reactions, static poses, or in-app animation and call the core widget feature complete.

## 2. Define the signature behaviors

The following are design targets, conditional on milestone 1.

| Behavior | Visual treatment | Small square | Wide rectangle |
| --- | --- | --- | --- |
| Playful action | Species-appropriate head tilt, paw bat, happy wiggle, hop or stretch; optional licking for suitable animals | Complete animal remains visible | Natural anatomy, room around the movement |
| Sleep on back | Belly up, curled paws, eyes closed; gentle breathing and snore bubble | Body fits compactly without clipped paws | Full body on a cushion with room for the snore bubble |
| Idle | Blinking, slight head tilt, small ear or tail motion | Strong facial expression | More room for body movement |
| Wake up | Stretch and return to idle | Compact stretch | Full-body stretch |

The playful action stays within the widget rectangle; it does not overlay other icons or the rest of the Home Screen. Sleeping on the back requires a proper belly-up drawing, not simply rotating an upright animal.

Use visual snoring in the widget. Optional snore sound belongs in the open app, controlled by the user. Continuous widget audio is not a launch dependency.

Offer Auto, Sleep, and Playful behavior choices. Auto favors sleeping during a configurable night period and occasional playful movement during awake periods. Behavior changes must use the rendering mechanism proved in milestone 1; arbitrary precise scheduling must not be assumed.

## 3. Build the smallest complete customer experience

1. Show an honest preview of the widget behavior and disclose that adoption is paid.
2. Choose animal, color/ombre, and accessories.
3. Generate one limited preview and choose a name.
4. Show “Adopt [name]” with subscription price and included features.
5. After purchase, prepare the full pet asset package and show progress. Preserve an already generated package so a retry or reinstall does not require creating a different pet.
6. Guide the user through manually adding the small or wide Home Screen widget, with previews of each. The app does not silently install the widget for them.
7. Provide a My Pet screen for appearance, behavior, and habitat choices.
8. Provide Photo Adventures: choose a personal photo, preview placement, use an image credit, and save/share the completed image.
9. Include credit balance, purchases, restore purchases, subscription management, and deletion of uploaded photos/pet data.

Prototype one dog first. The launch catalog targets all five requested animals; each species must pass the same playful/sleep and identity checks before it is offered. Define the gigglegoop's original body shape so its animation has stable anatomy.

## 4. Generate artwork once and reuse it

GPT Image 2 produces still images; local rendering supplies motion. Create a canonical pet reference, then derive a small set of consistent poses and reusable layers. Generate tongue/paw/face layers where useful; synthesize intermediate motion on the device rather than paying for every animation frame.

Store an asset manifest with the pet ID, reference image, species, colors, accessory details, pose images, anchors, crop bounds, renderer version, and package version. Validate identity, accessory placement, clean edges, and tiny-widget readability. Missing or inconsistent poses trigger a bounded repair process, with costs recorded.

Transparent output for `gpt-image-2` is currently documented as preview support. Test PNG alpha and fur edges before depending on it, and provide an asset-extraction route if it fails. OpenAI does not guarantee perfectly consistent characters across generations. [OpenAI image prompting](https://developers.openai.com/api/docs/guides/image-prompting), [Image generation limitations](https://developers.openai.com/api/docs/guides/image-generation#limitations)

Use the same canonical reference when inserting the pet into personal photos. Judge success by recognizability, placement, lighting, and preservation of the original photo. Widget motion and viewing already saved images consume no additional OpenAI tokens.

## 5. Technical structure

- Native SwiftUI iPhone app and a WidgetKit extension supporting `systemSmall` and `systemMedium`.
- A shared pet domain model and versioned asset package. An App Group makes selected pet data and cached assets available to the widget offline.
- A replaceable widget renderer containing any experimental animation method. Keep the proven main-app renderer separate, since the execution environments differ.
- A narrow App Intents layer for widget configuration and optional Feed/Play actions. Those buttons add interaction; they do not replace automatic motion.
- A backend for authenticated OpenAI generation/edit jobs, storage, cost logs, and credit accounting. Never put the OpenAI secret key in the app or widget.
- StoreKit subscriptions and consumable image credits, with server-verified entitlements and idempotent purchase/job handling.
- PhotosPicker for selected uploads and standard save/share flows. Retain source uploads only for the disclosed processing period and support deletion.

Choose the minimum supported iOS version after animation compatibility testing. Do not commit to a backend vendor until the proof of concept establishes the required asset pipeline.

## 6. Pricing and cost controls

Working proposal, pending measurement:

| Offer | Included |
| --- | --- |
| Free | One limited pet preview; no unlimited rerolls |
| $1.99/month or $20/year | One adopted pet, both animated widget sizes, basic habitats/behaviors, 5 standard image credits per month |
| $4.99 additional pack | 20 standard image credits |

This preserves the user's price targets while making the widget the recurring value. The original three-per-day idea can remain a pacing limit inside the monthly balance, rather than 90 included monthly images. Allowances and pack prices are proposals, not settled product rules. Define high-quality credit usage only after measuring its cost; purchased credits must not expire. [Apple purchase rules](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)

Planning assumptions: 15% store commission if eligible; $0.10 per satisfactory standard edit including inputs and regeneration attempts; no more than $0.75 for the complete initial pet package, including its preview. These are targets to test, not measured API costs. [Apple Small Business Program](https://developer.apple.com/app-store/small-business-program/)

At those assumptions, the $1.99 plan leaves about $1.19/month after commission and five edits, before hosting/support/acquisition; a $0.75 initial package reduces first-month contribution to about $0.44. The annual plan leaves about $10.25/year after commission, 60 edits, and that package, before other costs. Free previews for non-buyers reduce margins further.

Measure median and high-percentile costs for a complete adopted pet and each successful photo edit. Track billed generation attempts, refunds, failures, and repair work. Limit free preview abuse, prevent duplicate job charges, and cap automated regeneration. Revisit price or allowance if the complete package costs materially more than the target.

## 7. Delivery milestones

| Milestone | Deliverable | Completion condition |
| --- | --- | --- |
| 1: Animation feasibility | Small/wide widgets with prepared dog artwork and device recordings | Automatic playful/sleep works under the documented test conditions; shipping approach is defensible |
| 2: Art pipeline | Canonical pet, poses/layers, packaged local motion | Pet remains recognizable; asset cost and quality targets are measured |
| 3: Product flow | Create/name/adopt, My Pet, widget setup, configuration | A tester can create and install the pet without developer assistance |
| 4: Photos and payments | Photo Adventures, credits, subscriptions, restore | Charges, retries, cancellation, refunds, and purchase restoration behave correctly |
| 5: Beta | TestFlight build, full animal catalog, compatibility report | Feature works on beta users' real Home Screens and retention/cost evidence supports release |

Set the release schedule after milestone 1. Automatic animation is too central to give a credible full-build estimate before that result.

Track preview-to-purchase conversion, widget installation, seven/thirty-day retained users, repeat photo usage, cancellations, and contribution per subscriber. Release readiness requires both a reliable widget and measured economics.

## Immediate next build task

Create the isolated native widget experiment with one prepared dog in the small and wide sizes. Demonstrate automatic playful movement and belly-up snoring on real hardware, then record exactly which APIs, OS versions, and conditions make it work. This is the next implementation task; this document does not claim it has been built or verified.
