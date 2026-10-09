# MVP verification — October 8, 2026

Environment: Xcode 26.3; iPhone 17 Pro Simulator, iOS 26.3; Node.js 22.22.1. App and widget were built and installed with Simulator ad-hoc signing and App Group entitlements.

## Passed

- Native app build and launch; app and widget extension compile in Debug and Release configurations.
- Four free-text questions, sample generation, naming, saved pet, paywall after naming.
- Sample Pro activation grants 5,000 credits without a purchase.
- Small and wide widget previews, mood controls, original sleeping/playful illustration.
- Actual small Home Screen widget reads the same saved pet and Pro entitlement.
- Local backend connection from the actual app; missing OpenAI key shows a recoverable error and preserves the 250-credit trial balance.
- 22 backend tests pass, including HTTP job creation/retry/recovery, Pro gates, credit resets and animation-sheet charging/refunds.
- 6 iOS tests pass, including four-cell sprite extraction and widget entitlement expiry.

The implementation was also adjusted after Simulator inspection so Next/Generate and Welcome home remain accessible above the creation keyboard. Settings includes a keyboard dismissal action; errors are presented in the active sheet.

## Failed / unresolved

Automatic Home Screen motion did not occur with the timer/font-mask experiment enabled. Five snapshots captured were byte-identical while the saved pet's widget was visible. This is evidence against the current implementation on this simulator, not a claim that every possible iOS technique has been ruled out. Automatic looping remains an unmet essential requirement.

## Live provider validation

A project key is now configured in the ignored backend environment file (owner-only permissions). Model access returned HTTP 200. The initial transparent-background request failed with HTTP 400; the backend now requests opaque output and removes border-connected white. Real pet creation passed through the app, saved a named pet and charged exactly 250 credits. Two reference-based sheets generated successfully; visual inspection confirmed four playful frames and four belly-up sleeping/snoring frames. A two-reference photo edit also passed using a public NASA photograph and the generated pet; visual inspection confirmed the purple puppy beside the astronaut with the original scene retained. This is an AI-edited demonstration, not a historical photograph. Results, source credit and provider usage are in `live-validation`. Other species, pale edge mattes and personal-photo quality are not validated. Provider contract tests continue to use mocks.

## Not verified

The user reported creating App Store Connect products and supplied `500CreditPack`, `ProMonthly499` and `ProYearly4999`. Exact case-sensitive IDs now match the Swift app, local StoreKit catalog and backend allowlist; the pack continues to award 5,000 credits. The app rebuilt and launched, and all 22 backend tests passed after this change. Apple public root certificates are configured in the local Sandbox verifier, health reports purchases configured, and malformed signed transactions are rejected. All three product IDs were independently found on the existing Apple app; they currently have MISSING_METADATA status. Apple device signing now passes with the shared App Group present in both profiles. The signed version 1.0 (2) archive passed signature checks and export/upload succeeded; Apple processed the upload as COMPLETE and the build as VALID. Internal state is IN_BETA_TESTING; the build is available in the Internal Testing group with one tester. Published testing notes were read back and verified. Real Apple Sandbox purchases, renewals, refunds, App Store Server Notifications and physical-device widgets have not been tested. Local StoreKit configuration is included but is not accepted as an Apple-signed receipt by the server.

No public backend deployment, cross-device account restoration, retention/deletion workflow or production load test was completed.
