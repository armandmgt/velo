# frozen_string_literal: true

require_relative "lib/frontend_errors/version"

Gem::Specification.new do |spec|
  spec.name = "frontend_errors"
  spec.version = FrontendErrors::VERSION
  spec.authors = [ "Armand Mégrot" ]
  spec.email = [ "armand.megrot@gmail.com" ]

  spec.summary = "Report browser errors through Rails.error"
  spec.description = "Captures uncaught JavaScript exceptions, unhandled promise rejections, " \
                     "Stimulus controller errors and Turbo failures in the browser and reports " \
                     "them through ActiveSupport::ErrorReporter, so any subscriber (Solid Errors, " \
                     "Sentry, a logger) records them alongside server-side errors."
  spec.homepage = "https://github.com/armandmgt/velo"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "app/**/*", "config/**/*", "README.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "railties", ">= 7.1"
  spec.add_dependency "actionpack", ">= 7.1"
end
