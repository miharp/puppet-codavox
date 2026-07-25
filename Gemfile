# frozen_string_literal: true

source ENV['GEM_SOURCE'] || 'https://rubygems.org'

group :test do
  # metagem pulling in puppet-lint, rspec-puppet, rubocop and the rest
  gem 'voxpupuli-test', '~> 14.0', require: false
  # builds the test matrix from metadata.json
  gem 'puppet_metadata', '~> 6.1', require: false
end

# Used by gha-puppet's beaker workflow, which this module does not run yet.
group :system_tests do
  gem 'voxpupuli-acceptance', '~> 4.4', require: false
end

group :release do
  gem 'voxpupuli-release', '~> 5.3', require: false
end

gem 'rake', require: false

# openvox, not puppet. The two ship different strings implementations —
# openvox-strings and puppet-strings — and they disagree about whether a
# parameter whose default comes from module data has a documented default.
# Declaring puppet here made CI reject a REFERENCE.md that the voxbox container
# had just generated and validated as current.
gem 'openvox', ENV.fetch('OPENVOX_GEM_VERSION', ['>= 7', '< 9']), require: false, groups: [:test]
