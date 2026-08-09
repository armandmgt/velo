require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Velo
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # `ruby_fit` and `frontend_errors` are path gems, loaded by Bundler — Zeitwerk
    # must not also try to autoload their trees as application code.
    config.autoload_lib(ignore: %w[assets tasks templates ruby_fit frontend_errors])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #

    # No ActiveStorage variants are generated anywhere in the app; disable the
    # processor so boot doesn't try to load vips, which isn't in the Gemfile or
    # CI/dev images.
    config.active_storage.variant_processor = :disabled

    config.i18n.default_locale = :fr
  end
end
