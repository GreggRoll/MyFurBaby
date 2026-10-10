# Marketing page

Public website: https://greggroll.github.io/MyFurBaby/

Privacy policy: https://greggroll.github.io/MyFurBaby/privacy/

Use the privacy URL in the App Store Connect Privacy Policy field. Its source is `website/privacy/index.html`. Keep the policy aligned with actual data handling when providers, retention, or account controls change.

The static page lives in `website/`. The GitHub Pages workflow publishes that folder on `main`. It does not run or deploy the iOS app or backend.

## Preview and update

```sh
python3 -m http.server 8080 --directory website
```

Open http://localhost:8080. Edit `index.html`, `styles.css`, and `script.js`, then commit and push to `main` to publish.

The four supplied Home Screen recordings are cropped to the widget boundaries and encoded as H.264 MP4s in `website/assets/widget-*.mp4`. Audio and source metadata are removed. The hero, widget selector, background example, and Sterling feature play the actual recordings with muted inline autoplay and looping. The adventure presentation uses the bundled `adventures.mp4`. All videos share the pause/play controls, stop offscreen or when the tab is hidden, and pause with Reduce Motion. If autoplay is blocked, the controls offer Play animations. JPEG screenshots remain as poster images and for social previews.

## Add the App Store link at launch

Once the real listing URL is available:

1. Replace the noninteractive `.store-status` element with an anchor to the real App Store URL, change its small label to “DOWNLOAD ON THE”, and keep the existing styling.
2. Change “Coming soon” in the navigation, hero availability line, final section, page description, and social description to the launch message.
3. Update the App Store status in `README.md`.

Do not use a placeholder App Store URL. Until launch, the page intentionally displays “Coming soon”.

## Assets

- App icon: existing My Fur Baby branding.
- Widget examples: the four supplied screen recordings, with the original JPEGs as posters.
- Sterling animation: the supplied sleeping-widget recording. Adventure demo: the app’s existing onboarding clip.
- Social preview: a composition of the supplied clock and sleeping-tiger screenshots.

The page includes Pro/credit context, labels the GIF presentation demos, and uses real app features without invented testimonials or download claims.
