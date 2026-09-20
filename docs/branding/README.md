# Daily Rhythm identity and launch screen

20 September 2026. Implemented for development build **0.1.0 (3)**. The existing signed **0.1.0 (2)** archive is an earlier frozen candidate and does not contain this artwork or launch screen. A new archive and the remaining release checks are required before uploading build 3.

## Artwork

- [App icon master](app-icon-v2-source.png): mint daily cycle, ivory completion mark and coral next-step dot on deep teal. Generated with the built-in `image_gen` tool using the previous icon as the brand reference. [Exact selected prompts](prompts.json).
- Production icon: `DailyRhythm/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-v2.png`, normalized with `sips` to **1024×1024, RGB, no alpha**, with unrounded opaque edges. iOS applies its own mask. The generated 1254×1254 original is retained here.
- [Launch logo source](launch-logo-source.png): generated transparent mark. The same bytes live in `LaunchLogo.imageset`. Native template rendering uses its alpha silhouette and the adaptive `LaunchMark` tint: deep teal on light, mint on dark. This avoids carrying the unused ivory extraction's edge artifacts into the app; those discarded images are not shipped.
- [Original v1 icon](app-icon-v1.png) is preserved. `swift scripts/render_app_icon.swift` reproduces only that legacy file and cannot overwrite the selected v2 icon.

## Native launch implementation

`DailyRhythm/Resources/LaunchScreen.storyboard` is an app-only resource, referenced by `UILaunchStoryboardName` in the app's Info.plist. The generator owns its resource membership and build number; the widget does not bundle the storyboard. Both app and widget remain on the same version/build, bundle IDs, signing team and App Group.

The launch screen centers a 180-point transparent logo image, then native **Daily Rhythm** and **Habit OS** labels, with a 16-point upward optical offset and 24-point minimum safe-area side margins. Named colors provide light/dark appearances; background and text match the existing app theme values. Auto Layout adapts the composition to iPhone/iPad dimensions and supported orientations.

There is no artificial delay, timer, animation, new startup task, account gate or network request. iOS controls how long the static launch screen appears; fast and warm launches may show it only briefly. Store/onboarding/deep-link/notification code is unchanged.

## Design preview

Open [preview.html](preview.html) or serve this directory on loopback:

```sh
python3 -m http.server 8766 --bind 127.0.0.1 --directory docs/branding
```

The light/dark boards are explicitly labeled **design previews**, not Simulator screenshots or runtime acceptance evidence. They use the selected real artwork and matching tint/background/layout values. Do not submit them as App Store screenshots.

## Verification

- `python3 scripts/generate_project.py` and `--check` passed; all **4** generator/source-membership tests passed. All target guards and script sandboxing remain enabled.
- Closed/reopened only DailyRhythm in Xcode after generation, preserving the user's current **XREI-0001** destination. Actual **Build Succeeded at 21:00 TRT**. No Run or phone operation was performed.
- Signed generic-iOS **Release build succeeded at 21:01 TRT**. `codesign --verify --deep --strict` passed. The existing SSU-training diagnostic and signed-extension stripping warning remain; neither is a storyboard/asset failure.
- Inspected the actual Release bundle: build **3** in both app/widget, compiled `LaunchScreen.storyboardc` present only in the app, all four named launch assets present in `Assets.car`, and `LaunchLogo` compiled as **template**. The three named colors include dark appearances. Production icon is 1024×1024 with no alpha; no unassigned legacy icon remains in the icon set.
- Browser design boards and Xcode Interface Builder's native light/dark storyboard previews were visually inspected. The temporary Interface Builder appearance change was undone, leaving no unsaved edit. Native first-frame appearance, light/dark transition and cold launch on iPhone/iPad remain unverified; editor previews and existing Device Hub access problems are not reported as a runtime UI pass. No Simulator was created, deleted, reset or selected; no runtime changed. No personal store or backup was touched.
- Core tests were not repeated for this resource-only change. Prior core/privacy/upgrade results describe their earlier candidate and are not relabeled as new runtime verification.

Build logs and packaging inspection are local ignored artifacts in `ReleaseArtifacts/0.1.0-3/`. This work does not upload a build or update the live App Store listing.
