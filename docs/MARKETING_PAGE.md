# Marketing page

Public website: https://greggroll.github.io/MyFurBaby/

The static page lives in `website/`. The GitHub Pages workflow publishes that folder on `main`. It does not run or deploy the iOS app or backend.

## Preview and update

```sh
python3 -m http.server 8080 --directory website
```

Open http://localhost:8080. Edit `index.html`, `styles.css`, and `script.js`, then commit and push to `main` to publish.

The supplied Home Screen screenshots are cropped to the widget boundaries in `website/assets/widget-*.jpg`. The GIFs reuse `Resources/Onboarding/onboarding-widgets.mp4` and `onboarding-adventures.mp4`. Posters remain visible with JavaScript disabled, with Reduce Motion enabled, or when animations are paused. GIFs load near the viewport. The pause control affects both demos.

## Add the App Store link at launch

Once the real listing URL is available:

1. Replace the noninteractive `.store-status` element with an anchor to the real App Store URL, change its small label to “DOWNLOAD ON THE”, and keep the existing styling.
2. Change “Coming soon” in the navigation, hero availability line, final section, page description, and social description to the launch message.
3. Update the App Store status in `README.md`.

Do not use a placeholder App Store URL. Until launch, the page intentionally displays “Coming soon”.

## Assets

- App icon: existing My Fur Baby branding.
- Widget examples: the four screenshots supplied for this page.
- Animation and adventure demos: the app’s existing onboarding clips, converted to GIF.
- Social preview: a composition of the supplied clock and sleeping-tiger screenshots.

The page includes Pro/credit context, labels the GIF presentation demos, and uses real app features without invented testimonials or download claims.
