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
  require 'voxpupuli/release/rake_tasks'
rescue LoadError
  # voxpupuli-release is only available in the release gem group
else
  GCGConfig.user = 'miharp'
  GCGConfig.project = 'puppet-codavox'
end
