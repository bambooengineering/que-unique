# frozen_string_literal: true

require_relative "lib/que/unique/version"

Gem::Specification.new do |spec|
  spec.name          = "que-unique"
  spec.version       = Que::Unique::VERSION
  spec.authors       = ["Bamboo Engineering"]
  spec.email         = ["dev@bambooloans.com"]

  spec.summary       = "A gem that removes duplicates when multiple copies of a que job are enqueued."
  spec.homepage      = "https://github.com/bambooengineering/que-unique"
  spec.license       = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bambooengineering/que-unique"
  spec.metadata["changelog_uri"] = "https://github.com/bambooengineering/que-unique/CHANGELOG.md"
  spec.files = Dir["{lib}/**/*"]
  spec.require_paths = ["lib"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  spec.add_dependency "activerecord", "> 4.0", "< 6.0"
  spec.add_dependency "que", "~> 0.12"
  spec.add_development_dependency "combustion"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "que-testing"
  spec.add_development_dependency "rspec"
end
