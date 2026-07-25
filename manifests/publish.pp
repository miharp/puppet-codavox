# @summary Runs the codavox publisher, which serves versioned code to compilers.
#
# Include this on the node holding r10k's staging directory — normally the
# primary. The publisher seals each staged environment into a content-addressed
# `code_id`, materializes an immutable artifact for it, and serves both to
# compilers over mutual TLS using the Puppet certificate the node already has.
#
# Sealing happens when this service starts and on `SIGHUP`, not per request:
# walking and hashing an environment is far too expensive to repeat for every
# polling compiler, and two compilers polling either side of an r10k run would
# otherwise see different ids for one deploy. `systemctl reload codavox-publish`
# sends that signal, which is what r10k's `postrun` hook should call.
#
# Requires `codavox::staging`. Set `codavox::publish_allow_roles` to the
# `pp_role` values allowed to fetch code — including this node's own role if it
# also serves its own catalogs.
#
# @param service_name
#   The systemd service the package ships.
#
# @param service_ensure
#   Whether the service should be running.
#
# @param service_enable
#   Whether the service starts at boot.
#
# @param service_manage
#   Whether to manage the service at all.
#
# @example On a primary, with staging and the roles set in Hiera
#   include codavox::publish
#
class codavox::publish (
  String[1] $service_name = 'codavox-publish',
  Stdlib::Ensure::Service $service_ensure = 'running',
  Boolean $service_enable = true,
  Boolean $service_manage = true,
) {
  include codavox

  # Refusing to start is better than a publisher that comes up serving nothing:
  # compilers would poll an empty environment list and report success.
  if !$codavox::staging {
    fail('codavox::publish needs codavox::staging set to r10k\'s basedir, the directory the publisher seals')
  }

  if $service_manage {
    service { $service_name:
      ensure => $service_ensure,
      enable => $service_enable,
    }

    Class['codavox::config'] ~> Service[$service_name]
  }
}
