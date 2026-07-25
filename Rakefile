# frozen_string_literal: true

begin
  require 'voxpupuli/test/rake'
rescue LoadError
  # Allowed to fail, only needed in test
end

begin
  require 'voxpupuli/acceptance/rake'
rescue LoadError
  # Allowed to fail, only needed in acceptance
end

begin
  require 'puppet_blacksmith/rake_tasks'
rescue LoadError
  # Allowed to fail, only needed in release
end
