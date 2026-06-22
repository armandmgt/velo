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

## Release to TestFlight / App Store

Releases are managed with [fastlane](https://docs.fastlane.tools/) — metadata,
build numbers, and uploads stay on the command line instead of in App Store
Connect's web UI.

### One-time setup

1. **App Store Connect API key.** In App Store Connect → Users and Access →
   Integrations → App Store Connect API, generate a key with the **Admin**
   role (downgrade to **App Manager** after the first `produce` run if you
   prefer). Download the `.p8` (only available once) and note the **Key ID**
   and **Issuer ID**.
2. Drop the `.p8` at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`.
3. Export the IDs in your shell (a `.env` file in `native/ios/` works too,
   and is gitignored):
   ```bash
   export ASC_KEY_ID=ABCD1234EF
   export ASC_ISSUER_ID=69a6de70-…-…
   ```
4. Install gems: `cd native/ios && bundle install`.
5. Create the app record on App Store Connect (run once):
   ```bash
   bundle exec fastlane create_app
   ```

### Day-to-day

```bash
cd native/ios
mise run testflight   # → bundle exec fastlane beta
```

This regenerates the Xcode project if needed, fetches the latest TestFlight
build number from ASC, bumps to `latest + 1`, archives with Release signing,
and uploads. `MARKETING_VERSION` lives in `project.yml`; bump it there when
you cut a new marketing version.

When you're ready to push the current TestFlight build to App Store review:

```bash
mise run release      # → bundle exec fastlane release
```

## Not yet implemented

Native bridge components (custom toolbar buttons, notification badge, push
notifications) and a multi-tab layout are planned follow-ups. The web side
already ships the matching Stimulus bridge controllers under
`app/javascript/controllers/bridge/`.
