# Velo iOS (Hotwire Native)

Native iOS shell around the Velo web app, built with
[Hotwire Native](https://native.hotwired.dev/). It wraps the existing Rails
site in a `WKWebView`, shares its cookie session for auth, and presents screens
according to the path configuration served at `/configurations/ios_v1`.

## Prerequisites

- Xcode 17+ (tested with Xcode 26)
- [XcodeGen](https://github.com/yonyz/XcodeGen): `brew install xcodegen`

## Generate the Xcode project

The `.xcodeproj` is **not** committed — it's generated from `project.yml`:

```bash
cd native/ios
xcodegen generate
open Velo.xcodeproj
```

Re-run `xcodegen generate` whenever `project.yml` or the file layout changes.

## Run against the dev server

1. Start the backend from the repo root:
   ```bash
   docker compose up -d db
   bin/dev
   ```
2. In Xcode, pick an iOS Simulator and press **Run** (⌘R).

DEBUG builds point at `http://localhost:3000` (see `Sources/AppConfig.swift`).
The Simulator shares the host network, so `localhost` resolves directly; the
plain-HTTP exception for `localhost` lives in `Sources/Info.plist`. Release
builds target `https://velo.armandmgt.fr`.

Log in with your normal Velo credentials — the web login form renders inside
the native shell (without the web navbar, which `native.css` hides for native
clients).

## Layout

| File | Purpose |
| --- | --- |
| `project.yml` | XcodeGen project definition (committed) |
| `Sources/AppDelegate.swift` | Hotwire config + path-configuration loading |
| `Sources/SceneDelegate.swift` | Creates the `Navigator` and routes to the root URL |
| `Sources/AppConfig.swift` | Dev/prod base URLs |
| `Sources/Info.plist` | Scene manifest + dev ATS exception |
| `Resources/path-configuration.json` | Bundled fallback path config |

## Not yet implemented

Native bridge components (custom toolbar buttons, notification badge, push
notifications) and a multi-tab layout are planned follow-ups. The web side
already ships the matching Stimulus bridge controllers under
`app/javascript/controllers/bridge/`.
