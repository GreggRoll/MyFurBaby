# Puppy app icon

The approved purple puppy artwork is the source for the system app icon and all app branding. The opaque 1024 × 1024 master is in `Resources/Branding/my-fur-baby-icon.png`. Run `swift scripts/generate_assets.swift` from the project root to install it into `AppIcon.appiconset` and regenerate the compact 1×/2×/3× `FurBrandIcon.imageset` assets.

The shared `FurBrandIcon` view appears in the main app header, onboarding badge and birth animation, Pro header, Settings About section, and widget empty state. Functional symbols and each user's actual pet artwork remain separate from app branding. Both Debug and Release use the `AppIcon` asset, with Xcode producing iPhone and iPad system sizes. The next uploaded build will include the new App Store/TestFlight icon.

Validation: the app and widget extension built successfully and the app launched on the iOS 26.3 MyFurBaby Widget QA simulator. The compiled bundle declares `AppIcon` as its primary icon and contains iPhone and iPad icon renditions. The master, installed app icon, and approved generated image have identical SHA-256 hashes. Visual checks covered the app header, onboarding badge and birth animation, and the Home Screen widget empty state. Onboarding used a separate sample-mode preferences suite.

- [App header](screenshots/branding/app-header.jpg)
- [Onboarding](screenshots/branding/onboarding.jpg)
- [Home Screen widget](screenshots/branding/home-screen.jpg)
