# @summary Runs all of codavox on one node: publisher, agent, and server wiring.
#
# For an estate with a single OpenVox Server, where the node holding the code is
# also the node compiling catalogs. That is the most common Puppet topology, and
# the one with no other correct route to static catalogs: `static_catalogs`
# already defaults to true, but it does nothing without a `code_id_command`, and
# hand-written ones fail in ways that are hard to notice. A git SHA does not
# change when an uncommitted edit changes the served content, and a timestamp
# invents a version that describes nothing.
#
# The node seals its own basedir, serves it to itself over mutual TLS, and
# compiles from the unpacked version directory. The round trip is redundant on
# one machine, but it is the same code path every compiler uses, so a `code_id`
# in a catalog means exactly what it means everywhere else — and adding a
# compiler later changes nothing about how this node works.
#
# @note Two settings have no safe default and must be in Hiera:
#
#   ```yaml
#   codavox::basedir: /etc/puppetlabs/code/environments
#   codavox::agent_publisher: "https://%{trusted.certname}:8150"
#   ```
#
#   The basedir is r10k's, the directory the publisher seals. Leaving it at the
#   stock codedir means OpenVox Server keeps compiling from the staging tree
#   until the wiring flips, so the cutover costs no downtime. The publisher must
#   be named by certname, not localhost, because it presents this node's Puppet
#   certificate and the name has to verify against it.
#
# ## Why the server wiring waits
#
# `codavox::server` repoints `environmentpath` at a directory the agent fills.
# Pointing it there before the agent has converged stops catalog compilation.
# That is correct behavior, and survivable on a compiler, because the primary can
# still hand it a catalog that repairs it.
#
# On a single node it is not survivable that way: the agent that would apply the
# fix needs a catalog from the server it just broke, so the repair is an SSH
# session. This class therefore leaves the server alone until the
# `codavox_environments` fact reports the environment converged. The first run
# installs codavox and starts the publisher and agent; a later run, once there is
# something to serve, points OpenVox Server at it. Nothing needs sequencing by
# hand, and the node cannot lock itself out.
#
# The wiring only ever moves forward. If the environment later disappears, this
# class stops managing the server settings rather than removing them — reverting
# would restart puppetserver to reach a state that cannot compile static catalogs
# either, since `codavox code-id` still has no symlink to read.
#
# @param require_environment
#   The environment that must have converged before OpenVox Server is pointed at
#   codavox. One is enough: `environmentpath` covers them all, and an estate this
#   size is not usually waiting on a second.
#
# @param manage_server
#   Whether to wire OpenVox Server at all. Set false to run the publisher and
#   agent while catalog compilation stays on the stock codedir — the state a
#   first run passes through, made permanent.
#
# @param wait_for_convergence
#   Whether to hold the wiring back until the agent has converged. Turning this
#   off wires the server immediately, which on a single node risks a puppetserver
#   that cannot compile the catalog needed to fix it. Reasonable only when
#   restoring a node whose version directories are already in place.
#
# @param port
#   The publisher's port. Used only to build the example URL in the error raised
#   when `codavox::agent_publisher` is unset.
#
# @example A single-server estate, with the two settings above in Hiera
#   include codavox::standalone
#
# @example Keep compiling from the stock codedir for now
#   class { 'codavox::standalone':
#     manage_server => false,
#   }
#
class codavox::standalone (
  String[1] $require_environment = 'production',
  Boolean $manage_server = true,
  Boolean $wait_for_convergence = true,
  Stdlib::Port $port = 8150,
) {
  include codavox

  # codavox::publish already fails without a basedir. The agent's publisher is
  # read from the main class too, so it cannot be passed from here — ask for it
  # by name, and give the exact line rather than leaving an operator to work out
  # that localhost will not verify.
  if !$codavox::agent_publisher {
    $certname = $codavox::certname ? {
      undef   => $trusted['certname'],
      default => $codavox::certname,
    }
    fail("codavox::standalone needs codavox::agent_publisher set to this node's own publisher, for example https://${certname}:${port} — the certname, because the publisher presents this node's Puppet certificate and localhost would not verify against it") # lint:ignore:140chars
  }

  contain codavox::publish
  contain codavox::agent

  # The publisher has to be serving before the agent has anything to converge
  # against.
  Class['codavox::publish'] -> Class['codavox::agent']

  # An older agent, or one that has never converged, reports nothing. Both are
  # "not ready", which is the safe reading.
  $converged = $facts['codavox_environments'] ? {
    Hash    => $facts['codavox_environments'],
    default => {},
  }
  $ready = $require_environment in $converged

  if $manage_server and ($ready or !$wait_for_convergence) {
    # codavox::server draws its own edge after codavox::agent.
    contain codavox::server
  } elsif $manage_server {
    notice("codavox::standalone: leaving OpenVox Server on its current code until ${require_environment} has converged. Expected on a first run — the publisher and agent are running, and the next run wires the server.") # lint:ignore:140chars
  }
}
