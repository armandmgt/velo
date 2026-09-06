source "https://rubygems.org"

gem "activerecord-postgis-adapter"
gem "bcrypt", "~> 3.1.7"
gem "bootsnap", require: false
gem "data_migrate"
gem "httparty"
gem "image_processing", "~> 2.1"
gem "importmap-rails"
gem "jbuilder"
gem "kamal", require: false
gem "pg", "~> 1.5"
gem "propshaft"
gem "puma", ">= 5.0"
gem "rack-proxy"
gem "rails", "~> 8.1.2"
gem "rails_icons"
gem "rake-compiler"
gem "reactionview"
gem "rgeo"
gem "ruby_fit", path: "lib/ruby_fit"
gem "solid_cable"
gem "solid_cache"
gem "solid_errors", group: :production
# Not production-only, unlike solid_errors itself: it reports through Rails.error,
# so it's a no-op wherever nothing has subscribed.
gem "solid_errors-frontend", "~> 0.1"
gem "solid_queue"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "tailwind_merge", "~> 1.5"
gem "thruster", require: false
gem "turbo-rails"
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "launchy"
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "hotwire-spark"
  gem "rails-mcp-server"
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
