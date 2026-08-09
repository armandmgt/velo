# frozen_string_literal: true

module FrontendErrors
  class Engine < ::Rails::Engine
    isolate_namespace FrontendErrors

    # Serve app/assets/javascripts/frontend_errors.js through the host's asset
    # pipeline (Propshaft or Sprockets).
    initializer "frontend_errors.assets" do |app|
      app.config.assets.paths << root.join("app/assets/javascripts") if app.config.respond_to?(:assets)
    end

    # Importmap::Engine's own "importmap" initializer draws every path in
    # config.importmap.paths, so ours has to be appended before it runs.
    initializer "frontend_errors.importmap", before: "importmap" do |app|
      next unless app.config.respond_to?(:importmap)

      app.config.importmap.paths << root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << root.join("app/assets/javascripts")
    end

    # isolate_namespace keeps engine helpers out of the host's views, but
    # frontend_errors_tag has to be callable from the host layout.
    initializer "frontend_errors.helpers" do
      ActiveSupport.on_load(:action_view) do
        include FrontendErrors::TagsHelper
      end
    end
  end
end
