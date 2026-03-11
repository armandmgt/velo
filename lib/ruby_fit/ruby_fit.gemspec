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

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = [ "lib" ]

  spec.extensions = %w[ext/ruby_fit/extconf.rb]
end
