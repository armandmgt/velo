# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bin/dev                        # Start dev server (web + Tailwind watch via Foreman)
bin/rails test                 # Run all tests
bin/rails test test/path/file  # Run a single test file
bin/rails test:system          # Run system tests (Capybara/Selenium)
bin/rubocop -f github          # Lint Ruby code
bin/brakeman --no-pager        # Security scan
bin/rails db:prepare           # Create and migrate database
```

## Workflow

- Commit directly to the current branch (usually `main`); do not create new branches unless explicitly asked.

## Deployment

Deploy is manual via Kamal: commit your changes, then run `kamal deploy`.

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