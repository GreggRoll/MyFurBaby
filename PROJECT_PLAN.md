# My Fur Baby — MVP product plan

Updated October 8, 2026. This replaces the original $1.99/$20 concept.

## Product experience

Four free-text questions collect animal, color, style/accessories and personality. Accessories can be blank. Animals can be real or imaginary. The backend inserts the answers into a controlled plush-cartoon prompt template and generates a canonical pet with GPT Image 2. The user sees the pet, names it, saves it, and reaches the Pro paywall. A free account receives one 250-credit starter generation.

Pro unlocks animation generation, small square and medium rectangular Home Screen widgets, and photo adventures. Photo adventures send a selected personal photo plus the canonical pet reference to GPT Image 2 for insertion with matching lighting, shadows and scale. The user can save or share the finished image.

## Prices and credit rules

| Product | Price in USD | Allowance |
| --- | --- | --- |
| Pro monthly | $4.99/month | 5,000 credits per subscription month |
| Pro annual | $50/year | 5,000 credits each subscription month |
| Credit pack | $4.99 | 5,000 additional credits |

A pet creation or photo insertion costs 250 app credits. Each complete video animation costs 250 credits: playful, running and sleeping together cost up to 750, or 1,000 including the original still. Saved sequences replay for free. Subscription credits expire at the monthly reset; pack credits remain available. Pro entitlement is separate from credit balance. Video generation and background removal are separately billed by fal.ai and require cost measurement. The app explains the maximum charge before generation.

## Animation and widget status

Pet stills use GPT Image 2. Animations use fal.ai PixVerse V6 for continuous image-to-video motion, VEED animal segmentation for VP9 alpha, and FFmpeg for fixed-canvas RGBA extraction. Playful runs 3 seconds, run and sleep 4 seconds, at 15 FPS. Sleeping requires the supplied animal on its back or side with pronounced visual snoring and mouth-origin floating Zs; audio is disabled for widgets. Reclining pose checks and post-segmentation vector lettering protect this behavior. The app keeps and plays the full sequence. The current widget timer mask samples four frames from each mood. Existing four-cell sheets remain compatible. See [video animation details](docs/VIDEO_ANIMATION.md).

Both WidgetKit sizes load the selected saved pet through an App Group. Moods can be selected or switch by time of day. Widget timelines handle mood changes and membership expiry. Widgets can show the saved sleepy or playful pose, and tapping opens the app. Snoring is visual; widget audio is not implemented.

**Build 1.0 (6) fixes the motion placeholder rendering path.** Shared-container artwork fonts caused a likely device view-archive failure; ordinary PNG frames now use Bryce Bostwick’s bundled seconds-ligature mask. Physical-device looping remains unverified. See [widget animation implementation and TestFlight checks](docs/WIDGET_ANIMATION.md).

**Automatic looping in the actual Home Screen widget remains unresolved.** The timer/font-mask experiment stayed still in the iOS 26.3 Simulator: five screenshots were identical. The experiment is optional and labelled; there are no private clock APIs or third-party binary frameworks. Foreground animation is not evidence that automatic widget animation works. Because automatic motion is essential to this product idea, this MVP does not yet satisfy that release requirement. Test an approved, reliable implementation on physical devices before advertising it or launching around that promise.

## Economics to validate

5,000 credits buy 20 generated images. At current medium-quality 1024x1024 output pricing, those outputs alone cost about $1.06. Editing additionally charges for text and reference-image inputs. Source: [OpenAI image generation guide](https://developers.openai.com/api/docs/guides/image-generation#calculating-costs).

For planning, assume $0.10 all-in per successful image and 15% store commission; this is a scenario, not measured production cost or guaranteed eligibility. A fully used monthly allowance leaves approximately $2.24 ($4.99 × 0.85 − 20 × $0.10) before hosting, support, refunds, failed provider calls and acquisition. A fully used annual plan leaves about $18.50/year ($50 × 0.85 − 240 × $0.10). At 30% commission those figures fall to approximately $1.49/month and $11/year. The annual plan reaches zero contribution at about $0.177 per image with 15% commission, before other expenses. Using high quality for every call could wipe out the margin; medium is fixed in this build.

The backend records provider usage for later measurement. Free-generation abuse, refunded credits on failed billable requests, and malformed sprite sheets can increase cost. Validate real usage and acquisition cost in a small paid pilot. The credit math can support positive contribution; it does not establish demand, retention or overall profitability.

## Build and launch sequence

1. Run the checked-in iOS app and backend locally. Completed with sample UI and mocked-provider HTTP tests.
2. Configure an OpenAI project key and validate real creations, two-sheet animations, and photo edits. Real pet creation now passes in the app; both reference-based sheets and a public-photo insertion have been generated and inspected. Wider species and personal-photo validation remains.
3. Register app, widget App Group, subscription products and credit pack in Apple developer services. Test signed Sandbox purchases and notifications. Product IDs supplied from App Store Connect are now wired into the app, catalog and backend: `500CreditPack`, `ProMonthly499`, `ProYearly4999`. The local Sandbox verifier has Apple root certificates configured. Device signing and App Group profiles now pass, and a signed TestFlight build was uploaded. Real Sandbox purchase/notification tests remain incomplete.
4. Resolve automatic widget looping on current physical iPhones. Current simulator experiment failed to animate.
5. Add account recovery across devices, purchase reconciliation, data deletion/retention, hosted privacy/support pages, durable workers, abuse protection and spending controls before a public paid release.

Version 1.0 (2) was uploaded to TestFlight on October 8, 2026; Apple processed the build as VALID; it is IN_BETA_TESTING in the Internal Testing group, with verified testing notes. No App Store submission has been made.
