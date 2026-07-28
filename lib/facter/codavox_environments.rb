# frozen_string_literal: true

require 'yaml'

# What codavox is currently serving on this node, as `environment => code_id`.
#
# Read from the environment symlinks under codavox's environmentpath, the same
# place `codavox code-id` reads, so the fact and the command cannot disagree.
# Nothing is shelled out to: this runs on every agent run, and `code-id` is on
# the catalog-compile path where a fork is exactly what codavox avoids.
#
# The fact exists so a manifest can tell whether the agent has converged before
# pointing OpenVox Server at codavox. That ordering matters most on a node that
# is its own compiler: repointing `environmentpath` at a directory the agent has
# not filled yet stops catalog compilation, and the agent that would repair it
# needs a catalog from the server it just broke.
#
# An empty hash means "nothing converged yet": a true statement about a node
# that has only just installed codavox, and a useful one to branch on.
Facter.add(:codavox_environments) do
  confine kernel: 'Linux'

  # The path is configurable, so read the node's own config rather than assuming
  # the default. A fact that looked in the wrong directory would report nothing
  # converged and quietly stop a primary from ever wiring its own server.
  def self.environment_path
    default = '/opt/puppetlabs/codavox/environments'
    config = '/etc/codavox/config.yaml'
    return default unless File.readable?(config)

    parsed = YAML.safe_load(File.read(config))
    return default unless parsed.is_a?(Hash)

    path = parsed['environmentpath']
    (path.is_a?(String) && !path.empty?) ? path : default
  rescue StandardError
    # A malformed config is codavox's problem to report, loudly, when it starts.
    # A fact that raised here would fail every catalog compile on the node over
    # a file the fact only consults for a path.
    default
  end

  setcode do
    envdir = environment_path
    result = {}

    if File.directory?(envdir)
      Dir.children(envdir).sort.each do |name|
        link = File.join(envdir, name)
        next unless File.symlink?(link)

        # The agent unpacks to <environment>_<code_id>, so split on the last
        # underscore: an environment name may contain underscores, a hex code_id
        # never does.
        #
        # All three parts are checked, and the name has to match the environment
        # the symlink is for. rpartition with no separator present returns the
        # whole string as the tail, so a link pointing at some unrelated
        # directory would otherwise be reported as that directory's name: a
        # code_id that describes nothing, and the fact would look converged.
        # Reporting nothing is correct here: the state on disk is not one the
        # agent produces.
        env, sep, code_id = File.basename(File.readlink(link)).rpartition('_')
        next if sep.empty? || code_id.empty? || env != name

        result[name] = code_id
      end
    end

    result
  end
end
