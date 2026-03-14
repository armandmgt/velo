# frozen_string_literal: true

require_relative "lib/ruby_fit/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_fit"
  spec.version = RubyFit::VERSION
  spec.authors = [ "Armand Mégrot" ]
  spec.email = [ "armand.megrot@gmail.com" ]

  spec.summary = "RubyFit"
  spec.description = "RubyFit"
  spec.homepage = "https://github.com/armandmgt/velo"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "ext/**/*"]
  spec.require_paths = [ "lib" ]

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = [ "lib" ]

  spec.extensions = %w[ext/ruby_fit/extconf.rb]
end
