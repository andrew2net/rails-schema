# frozen_string_literal: true

require_relative "lib/rails/schema/version"

Gem::Specification.new do |spec|
  spec.name = "rails-schema"
  spec.version = Rails::Schema::VERSION
  spec.authors = ["Andrei Kislichenko"]
  spec.email = ["android.2net@gmail.com"]

  spec.summary = "Interactive HTML visualization of your Rails database schema"
  spec.description = "Introspects a Rails app's models, associations, and columns, then generates " \
                     "a single self-contained HTML file with an interactive entity-relationship diagram."
  spec.homepage = "https://github.com/nicholaides/rails-schema"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 6.0"
  spec.add_dependency "railties", ">= 6.0"
end
