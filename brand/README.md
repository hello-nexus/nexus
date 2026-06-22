# Nexus brand masters

Canonical 1024x1024 source artwork for the Nexus app mark (the interlocking "N"),
plus the traced vector mark. All derived assets (platform app icons, favicons,
the in-app logo, the iOS in-app mark) are **generated from these** - regenerate
from here, do not hand-edit the derived files.

## Source files

| File | Background | Alpha | Source for |
|------|------------|-------|-----------|
| `NexusLogoMarkColorAlpha.png` | none (transparent) | yes | **iOS + macOS app icons** (the OS supplies the rounded tile background + light/dark/tinted theming, so the mark must be transparent, not on a baked tile). Also the iOS in-app mark and the grayscale tinted variants. |
| `NexusLogoMarkColorSquircleAlpha.png` | black squircle | yes (corners) | **Windows + Linux icons** (these do not auto-mask, so the rounded superellipse tile is baked in with transparent corners). |
| `NexusLogoMarkAlpha.png` | none (transparent) | yes | White monochrome mark. Traced to the vector mark (`nexus-mark.svg`, favicon, `NexusBrand` component). |
| `NexusLogoMarkColor.png` | full-bleed black | no | Opaque full-bleed color mark. Kept for reference / opaque contexts; not currently a build input. |
| `NexusLogoMarkBW.png` | full-bleed | no | Black-and-white variant. Not currently assigned to any platform. |
| `nexus-mark.svg` | none | - | Vector mark traced from `NexusLogoMarkAlpha.png`, `fill="currentColor"`. The single source of truth for the in-app SVG logo. |

## Derived assets and where they live

**App icons**
- iOS: `nexus-ios/Nexus/Assets.xcassets/AppIcon.appiconset/` <- `ColorAlpha`
- macOS: `nexus-service/Bundled/macos/AppIcon.icns` + `Assets.xcassets/AppIcon.appiconset/` <- `ColorAlpha`
- Windows: `nexus-service/icon.ico` + `nexus-overlay/icon.ico` <- `ColorSquircleAlpha`
- Linux: `nexus-service/Bundled/linux/nexus-{16..512}.png` <- `ColorSquircleAlpha`

**In-app logo (web)** - all driven by the traced mark
- `nexus-web/src/components/icons/NexusBrand.tsx` `NexusMark` (`fill="currentColor"`, traced from `NexusLogoMarkAlpha.png`). Rendered in the dashboard sidebar top-left (`app/sidebar.tsx`, mark + wordmark when expanded), the pair-redirect splash, and the "Open in App" banner.
- `nexus-web/public/favicon.svg` + `nexus-service/wwwroot/favicon.svg` - gradient version of the same traced mark (browser tab, PWA manifests for both dashboard and `/panel/phone`).
- The `NexusWordmark` ("nexus" lettering) in `NexusBrand.tsx` is still traced from the old `LogoWithMark.png` and has not been updated.

**In-app logo (iOS)**
- `nexus-ios/Nexus/Assets.xcassets/NexusLogoMark.imageset/` (color mark) <- `ColorAlpha`. Rendered on the onboarding Welcome page (`OnboardingFlow.swift`) and the mobile connect screen (`NexusApp.swift` `ConnectionLoadingView`, shown while the panel loads).

## Regenerate

App icons: resize `ColorAlpha` into the iOS/macOS appiconsets (+ `_tinted` grayscale) and run `iconutil -c icns`; `magick <Squircle> -define icon:auto-resize=256,128,96,64,48,32,16` for the `.ico`s; resize `Squircle` into the Linux `nexus-*.png` set.

Vector mark: `magick NexusLogoMarkAlpha.png -alpha extract -threshold 50% -negate mark.pbm && potrace mark.pbm -s --tight -O 1 -t 5 -o nexus-mark.svg`, then propagate the paths into `favicon.svg` (gradient fill) and `NexusBrand.tsx` `MARK_PATHS` (currentColor).
