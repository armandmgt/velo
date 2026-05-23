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

## Deployment

Deploy is manual via Kamal: commit your changes, then run `kamal deploy`.

## Architecture

**Velo** is a Rails 8.1 cycling/running activity tracker — a self-hosted Strava alternative. French is the default locale (`i18n.default_locale = :fr`).

**Stack:** Rails 8.1, PostgreSQL + PostGIS, Hotwire (Turbo + Stimulus), Tailwind CSS, Importmap (no Node build step), Solid Cache/Queue/Cable/Errors, Active Storage, Kamal for deployment.

**Frontend:** ERB views with Stimulus controllers for interactivity. MapLibre GL for GPS maps, Chart.js for activity metrics. No separate JS build — everything goes through Importmap (`config/importmap.rb`).

### Core Models

- **User** — `has_secure_password`, `has_many :sessions, :activities`
- **Activity** — belongs to User, `has_one_attached :fit_file`, `has_many :activity_data_points`. Includes `ActivityCharts` concern (provides `chart_data` for speed/cadence/power/heart_rate). Supports `bike` and `run` sport types.
- **ActivityDataPoint** — per-second metrics (speed, cadence, power, heart_rate) with PostGIS Point geometry for location
- **Session** — custom session model (not Rails default); stores `user_agent` and `ip_address`
- **Current** — thread-local `Current.session` / `Current.user` via `Authentication` concern on ApplicationController

### FIT File Processing Pipeline

1. User uploads `.fit` (or `.zip` from Strava export)
2. `ActivitiesController#create` or `StravaImportService` invokes `Activity#parse_fit_file()`
3. `FitExtractor` (callback handler in `app/lib/`) uses vendored `RubyFit::Parser` (`lib/ruby_fit/`)
4. Extracts metrics → creates `ActivityDataPoint` records
5. Reverse geocodes first valid GPS point via `NominatimClient` → sets `activity.location`
6. Builds PostGIS LineString path from all valid GPS points

### Key Patterns

- **Authentication:** Signed cookies (`httponly`, `same_site: :lax`), `Current` model for thread-local context. No Devise.
- **Geospatial:** RGeo with simple Mercator factory. Activity paths stored as PostGIS LineString; data points as PostGIS Point.
- **Multiple databases:** `primary`, `solid_cache`, `solid_queue`, `solid_cable`, `solid_errors` — configured in `config/database.yml`.
- **Admin namespace:** `Admin::UsersController` under `/admin` with `admin: true` route constraint.
- **Schema format:** SQL (`db/schema.sql`), not Ruby — required by PostGIS.
- **Strava import:** `StravaImportsController` + `StravaImportService` handle ZIP extraction, `.fit` / `.fit.gz` processing, and deduplication.