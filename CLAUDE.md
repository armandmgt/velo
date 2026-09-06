# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Setup

After a fresh clone (or worktree creation), compile the vendored `ruby_fit` native
extension before running anything — the app won't boot without it:

```bash
cd lib/ruby_fit && rake compile
```

Running the native iOS/Android apps additionally requires Xcode / the Android
SDK, plus the per-platform `mise` tasks under `native/<platform>/` — see
[Native apps (Hotwire Native)](#native-apps-hotwire-native) below.

## Commands

```bash
docker compose up -d db        # Start PostgreSQL + PostGIS (dev/test DB lives here, NOT brew postgres)
bin/dev                        # Start dev server (web + Tailwind watch via Foreman)
bin/rails test                 # Run all tests
bin/rails test test/path/file  # Run a single test file
bin/rails test:system          # Run system tests (Capybara/Selenium)
bin/rubocop -f github          # Lint Ruby code
bin/brakeman --no-pager        # Security scan
bin/rails db:prepare           # Create and migrate database
bin/rails db:migrate:with_data # Run schema + data migrations (data_migrate gem)
```

The database runs in Docker (`docker-compose.yml`: `postgis/postgis:17-3.5`, role `velo`,
db `velo_development`, port 5432). Always use `docker compose up -d db` — do not start a
locally installed (e.g. Homebrew) Postgres, which won't have this data.

**Dev login:** the dev DB has a ready user (`test@example.com` / password `dev`), and the
login form pre-fills both fields, so to sign in (web or the native shells against the dev
server) just open the login page and submit — no typing needed. Don't change this user's
password; the pre-fill expects `dev`.

## Workflow

- Commit directly to the current branch (usually `main`); do not create new branches unless explicitly asked.

### Pull Requests

- Open PRs with `gh pr create --base main`.
- **Capturing UI screenshots:** reuse the Capybara/Selenium system-test harness — write a throwaway test under `test/system/` that logs in (`login(users(:one))`, password `password`), opens the UI, and calls `page.save_screenshot(Rails.root.join("tmp/<name>.png").to_s)`, then delete the test after the run. **Always capture both a desktop and a mobile view** (not just one). For the mobile view, resize first: `page.driver.browser.manage.window.resize_to(390, 844)`, then re-`visit` and save a separate `<name>-mobile.png`. Upload both to S3 and embed both in the PR body.
  - Before running, build CSS with `bin/rails tailwindcss:build` (`bin/rails server` alone does **not** compile Tailwind, so screenshots come out unstyled).
  - The test DB load shells out to `psql`, but the default `psql` is a mise shim with no version set. Put a real client on `PATH` and pass connection env vars: `export PATH="/opt/homebrew/Cellar/libpq/18.3/bin:$PATH" PGHOST=localhost PGUSER=velo PGPASSWORD=password`. If the test DB is stale, drop/recreate `velo_test` and load `db/structure.sql` with that same `psql`.
- **Attaching screenshots to a PR:** the GitHub repo is **private**, so GitHub will not render images from `raw.githubusercontent.com` or repo blob URLs. Upload the PNG to the public S3 bucket and embed its https URL directly in the PR body — no drag-drop needed.
  - **Bucket:** `your-screenshot-bucket` (region `eu-west-3`, personal account `AWS_ACCOUNT_ID`). Objects under the `screenshots/` prefix are world-readable via a public bucket policy; use an unguessable UUID filename so the URL isn't discoverable.
  - **Credentials:** the `aws` CLI is a fish function (`docker run … amazon/aws-cli:latest`) not available in Claude's `zsh`, so invoke the container directly. Creds live in `~/.aws` under the `production` profile (account `AWS_ACCOUNT_ID` — *not* the expired `default`/Cashbee one). Mount `~/.aws` → `/root/.aws` and pass `-e AWS_PROFILE=production`.
  - **Docker file-sharing gotcha:** Docker Desktop shares `/Users` but **not** `/tmp`. Mount the repo/worktree root (it's under `/Users`) at `/aws` and reference the screenshot by its repo-relative path, e.g. `tmp/foo.png` → `/aws/tmp/foo.png`.
  - **Upload + URL** (run from the repo root; substitute the worktree path as `$ROOT`):
    ```bash
    ROOT="$(git rev-parse --show-toplevel)"
    KEY="screenshots/$(uuidgen | tr 'A-Z' 'a-z').png"
    docker run --rm --volume ~/.aws:/root/.aws --volume "$ROOT":/aws --net=host \
      -e AWS_PROFILE=production amazon/aws-cli:latest \
      s3 cp "/aws/tmp/<name>.png" "s3://your-screenshot-bucket/$KEY" --content-type image/png
    # Public URL (embed in PR body as ![screenshot](URL)):
    echo "https://your-screenshot-bucket.s3.eu-west-3.amazonaws.com/$KEY"
    ```
  - Verify the object is live with `curl -s -o /dev/null -w '%{http_code} %{content_type}\n' "$URL"` (expect `200 image/png`) before relying on the PR rendering it.

## Deployment

Deploy is manual via Kamal: commit your changes, then run `kamal deploy`.

## Native apps (Hotwire Native)

The Rails app is wrapped by native iOS and Android apps under `native/`, using
Hotwire Native (Strada bridge). The web side and the native shells share
identifier `fr.armandmgt.velo`.

- **Layout:** `native/ios/` is an Xcode project — generated from `project.yml`
  via `xcodegen`. `native/android/` is a Gradle project.
- **Run them:** each folder has a `mise.toml` exposing platform tasks.
  - `cd native/ios && mise run debug` — boots an iOS simulator (auto-picks an
    available iPhone), regenerates `Velo.xcodeproj` via `xcodegen` if missing,
    builds the Debug scheme, installs to the simulator, and launches the app.
    The `simulator` task can be run alone to just boot a device.
  - `cd native/android && mise run debug` — boots an emulator (first available
    AVD) if none is attached, then `./gradlew :app:installDebug` and starts
    `fr.armandmgt.velo/.main.MainActivity`. The `emulator` task boots alone.
- **Verifying native changes — use Maestro, not `simctl` screenshots.** To debug
  or verify a native change, drive the running app with Maestro and read state
  from the accessibility tree; don't eyeball `xcrun simctl io … screenshot` PNGs.
  The Maestro binary is at `~/.maestro/bin/maestro` (not on `PATH`).
  - `maestro hierarchy` dumps the on-screen tree as JSON. It **exposes WebView
    content** (activity names, section headers, tab labels appear as
    `accessibilityText`/`text`), so use it to discover and confirm locators
    instead of reading pixels.
  - Flows live in `native/{ios,android}/maestro/*.yaml` (tag `regression`). Run
    one with `maestro test native/ios/maestro/<flow>.yaml`, or the whole suite
    with `maestro test native/ios/maestro/`. Keep the iOS and Android flows as
    mirrors. **Commit a flow when it guards a feature; discard throwaway
    debugging flows.**
  - Gotchas: after a login or tab-switch transition, insert
    `waitForAnimationToEnd` before asserting WebView text — the first query
    otherwise races the transition and the element reads as not-visible. A
    CSS-uppercased string (e.g. `text-transform` headings) surfaces uppercased on
    iOS but DOM-cased on Android, so match it with a tolerant alternation like
    `"ACTIVITÉS RÉCENTES|Activités récentes"`. `record_flow` drops a
    `record-review.png` in the CWD (a `takeScreenshot` artifact) — don't commit it.
- **Path configuration:** native apps fetch routing rules pre-login from
  `ConfigurationsController` (`/configurations/ios_v1`, `/configurations/android_v1`,
  both `allow_unauthenticated_access`). `MODAL_PATTERNS` (routes ending in
  `/new` or `/edit`) present modally; `AUTH_PATTERNS` (`/session/new`,
  `/users/new`) disable pull-to-refresh; everything else pushes onto the
  native nav stack. Android rules additionally route every URL to
  `hotwire://fragment/web`.
- **Bridge components:** Stimulus controllers under
  `app/javascript/controllers/bridge/` (`navbar_buttons`, `notification_count`,
  `push_subscription`) implement the web side via `@hotwired/hotwire-native-bridge`
  (pinned in `config/importmap.rb`). Elements opt in with
  `data-controller="bridge--<name>"` and `data-bridge-*` attributes — e.g.
  `data-bridge-ios-image` / `data-bridge-android-image` carry SF Symbol /
  Material icon names that the native shell renders into its nav bar.
- **Native-only styling:** `app/assets/stylesheets/native.css` ships overrides
  scoped to the native webviews (hide the web navbar, etc.).

## Architecture

**Velo** is a Rails 8.1 cycling/running activity tracker — a self-hosted Strava alternative. French is the default locale (`i18n.default_locale = :fr`).

**Stack:** Rails 8.1, PostgreSQL + PostGIS, Hotwire (Turbo + Stimulus), Tailwind CSS, Importmap (no Node build step), Solid Cache/Queue/Cable/Errors, Active Storage, Kamal for deployment.

**Frontend:** ERB views with Stimulus controllers for interactivity. MapLibre GL for GPS maps, Chart.js for activity metrics. No separate JS build — everything goes through Importmap (`config/importmap.rb`).

### Core Models

- **User** — `has_secure_password`, `has_many :sessions, :activities`, `has_one :igpsport_connection`
- **Activity** — belongs to User, `has_one_attached :fit_file`, `has_many :activity_data_points`. Includes `ActivityCharts` concern (provides `chart_data` for speed/cadence/power/heart_rate). The `sport` enum spans 14 types (`bike`, `mountain_bike_ride`, `gravel_ride`, `run`, `trail_run`, `hike`, `swim`, …); `SPORT_CATEGORY` groups them into `:cycling` / `:running` / `:other` (`Activity#sport_category`).
- **ActivityDataPoint** — per-second metrics (speed, cadence, power, heart_rate) with PostGIS Point geometry for location
- **Session** — custom session model (not Rails default); stores `user_agent` and `ip_address`
- **IgpsportConnection** — belongs to User; stores `encrypts`-ed iGPSport `email` / `password` / `access_token` for automatic sync
- **Current** — thread-local `Current.session` / `Current.user` via `Authentication` concern on ApplicationController

The root page (`/`) is the stats dashboard — `activity_feeds#index`.

### Activity Import Pipeline

Activities come from three sources, all converging on the extractors in `app/lib/`:

1. **Direct upload** — `ActivitiesController#create` dispatches by extension: `.gpx` → `Activity#parse_gpx_file` (`GpxExtractor`, Nokogiri-based), otherwise `Activity#parse_fit_file` (`FitExtractor`, vendored `RubyFit::Parser` in `lib/ruby_fit/`).
2. **Strava export** — `StravaImportService` walks the ZIP, handling `.fit` / `.fit.gz` / `.gpx` / `.gpx.gz` (gzip-decompressed first), with deduplication.
3. **iGPSport sync** — `IgpsportSyncJob` (recurring hourly, see below) runs `IgpsportSyncService`, which uses `IgpsportClient` to authenticate and download rides.

All extractors: extract metrics → create `ActivityDataPoint` records → reverse geocode the first valid GPS point via `NominatimClient` (resolved to town/commune level, skipped on bulk imports via `reverse_geocode: false`) → build a PostGIS LineString path from all valid GPS points.

### Key Patterns

- **Authentication:** Signed cookies (`httponly`, `same_site: :lax`), `Current` model for thread-local context. No Devise.
- **Geospatial:** RGeo with simple Mercator factory. Activity paths stored as PostGIS LineString; data points as PostGIS Point.
- **Multiple databases:** `primary`, `solid_cache`, `solid_queue`, `solid_cable`, `solid_errors` — configured in `config/database.yml`.
- **Admin namespace:** `Admin::UsersController` under `/admin` with `admin: true` route constraint.
- **Schema format:** SQL (`db/schema.sql`), not Ruby — required by PostGIS.
- **Strava import:** `StravaImportsController` + `StravaImportService` handle ZIP extraction, `.fit` / `.fit.gz` / `.gpx` / `.gpx.gz` processing, and deduplication.
- **iGPSport sync:** `IgpsportConnection` (per-user, encrypted credentials) managed via `igpsport_connection` controller. `IgpsportSyncService` + `IgpsportClient` pull rides; `IgpsportSyncJob` runs hourly (`config/recurring.yml`, Solid Queue).

## Agent skills

### Issue tracker

Issues and specs live as **GitHub issues** (`gh` CLI), inferred from the `origin` remote. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.