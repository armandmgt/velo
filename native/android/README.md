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

## Not yet implemented

Native bridge components (toolbar buttons, notification badge, push) and a
bottom-tab layout are planned follow-ups. The web side already ships the
matching Stimulus bridge controllers under
`app/javascript/controllers/bridge/`.
