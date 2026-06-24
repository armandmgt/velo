# Velo Android (Hotwire Native)

Native Android shell around the Velo web app, built with
[Hotwire Native](https://native.hotwired.dev/). It wraps the existing Rails
site in a `WebView`, shares its cookie session for auth, and presents screens
according to the path configuration served at `/configurations/android_v1`.

## Prerequisites

- JDK 17+
- Android SDK (compileSdk 35, minSdk 28) — e.g. via Android Studio
- An Android emulator or device

## Configure the SDK location

Create `native/android/local.properties` (gitignored) pointing at your SDK:

```properties
sdk.dir=/Users/<you>/Library/Android/sdk
```

## Build & run

1. Start the backend from the repo root:
   ```bash
   docker compose up -d db
   bin/dev
   ```
2. Build and install on a running emulator:
   ```bash
   cd native/android
   ./gradlew :app:installDebug
   adb shell am start -n fr.armandmgt.velo/.main.MainActivity
   ```
   Or open `native/android` in Android Studio and press **Run**.

DEBUG builds point at `http://10.0.2.2:3000` — the alias the Android emulator
uses to reach the host's `localhost` (see `app/build.gradle.kts`,
`BuildConfig.BASE_URL`). Cleartext HTTP to that host is whitelisted in
`res/xml/network_security_config.xml`; production
(`https://velo.armandmgt.fr`) stays HTTPS-only. Release builds target
production.

Log in with your normal Velo credentials — the web login form renders inside
the native shell (the web navbar is hidden for native clients by `native.css`).

## Layout

| Path | Purpose |
| --- | --- |
| `app/build.gradle.kts` | App module, deps, dev/prod `BASE_URL` |
| `…/VeloApplication.kt` | Hotwire config + path-configuration loading |
| `…/main/MainActivity.kt` | `HotwireActivity` with the single navigator host |
| `…/features/web/WebFragment.kt` | Default web destination (`hotwire://fragment/web`) |
| `res/layout/activity_main.xml` | Single `NavigatorHost` |
| `res/xml/network_security_config.xml` | Dev cleartext whitelist |
| `app/src/main/assets/json/path-configuration.json` | Bundled fallback path config |

## Release to Google Play (internal track → production)

Releases are managed with [fastlane](https://docs.fastlane.tools/) — version
codes, AAB uploads, and track promotions stay on the command line instead of
in the Play Console web UI. The internal testing track is Android's
TestFlight equivalent: instant distribution to a whitelisted tester list, no
review wait.

### One-time setup

1. **Release keystore.** Generate one and stash it outside the repo (or in
   `native/android/` — `.jks` files are gitignored):
   ```bash
   cd native/android
   keytool -genkey -v -keystore velo-release.jks -alias velo \
     -keyalg RSA -keysize 2048 -validity 10000
   cp keystore.properties.example keystore.properties
   # then edit keystore.properties with the real passwords
   ```
   **Back up the keystore** — losing it means you can never update the app
   under the same package name.

2. **Create the app in Play Console.** Go to
   [play.google.com/console](https://play.google.com/console), create a new
   app `Velo`, then fill out the mandatory store listing (short/long
   description, feature graphic, screenshots, content rating, target
   audience, data safety, privacy policy URL). Google requires the **first**
   AAB to be uploaded via the web UI — `fastlane supply` cannot create a new
   app. Build one with `./gradlew :app:bundleRelease` (output:
   `app/build/outputs/bundle/release/app-release.aab`) and upload it to the
   **internal** testing track from the Play Console. All subsequent uploads
   go through fastlane.

3. **Service account for the Play Developer API.**
   - In Play Console → Setup → API access, link a Google Cloud project (or
     create one), then create a new service account.
   - In Google Cloud → IAM, create a JSON key for the service account and
     download it (only available once).
   - Back in Play Console → Users and permissions, invite the service
     account's email and grant it **Admin (all permissions)** for the Velo
     app (or at minimum: Release manager + view app information).

4. **Drop the JSON key** at
   `~/.config/play-publisher/velo-play-publisher.json` (or set
   `PLAY_STORE_JSON_KEY=/path/to/key.json`).

5. **Install gems:**
   ```bash
   cd native/android
   bundle install
   ```

### Day-to-day

```bash
cd native/android
mise run testflight   # → bundle exec fastlane beta
```

This fetches the highest `versionCode` from the Play internal track, bumps
to `latest + 1`, builds a signed AAB with that code (via
`-Pvelo.versionCode=N` — no file mutation), and uploads to the internal
track. `versionName` lives in `app/build.gradle.kts`; bump it there when you
cut a new marketing version.

When the current internal build looks good, promote it to production:

```bash
mise run release      # → bundle exec fastlane release
```

This does not re-upload — it just moves the existing artifact from `internal`
to `production`.

## Not yet implemented

Native bridge components (toolbar buttons, notification badge, push) and a
bottom-tab layout are planned follow-ups. The web side already ships the
matching Stimulus bridge controllers under
`app/javascript/controllers/bridge/`.
