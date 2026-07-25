# @summary Runs the codavox agent, converging this compiler onto the publisher.
#
# Include this on each compiler. The agent polls the publisher, fetches any
# artifact it does not already hold, verifies it by resealing the unpacked tree —
# proving the content is what the `code_id` names, not merely that the bytes
# arrived intact — and then swaps the environment symlink with a single
# `rename(2)`.
#
# Compilers poll; nothing is pushed to them. That is the property the project
# exists for: a compiler that was down during a deploy catches up on its own next
# poll, with no event to replay and no operator intervention. It also means a
# publisher outage degrades to "no new deploys" rather than "no catalogs".
#
# Requires `codavox::agent_publisher`.
#
# Include `codavox::server` as well to point OpenVox Server at the code this
# deploys. Order matters on a first run — see that class.
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
# @example On a compiler, with the publisher set in Hiera
#   include codavox::agent
#
class codavox::agent (
  String[1] $service_name = 'codavox-agent',
  Stdlib::Ensure::Service $service_ensure = 'running',
  Boolean $service_enable = true,
  Boolean $service_manage = true,
) {
  include codavox

  if !$codavox::agent_publisher {
    fail('codavox::agent needs codavox::agent_publisher set to the publisher URL, for example https://puppet.example.com:8150')
  }

  if $service_manage {
    service { $service_name:
      ensure => $service_ensure,
      enable => $service_enable,
    }

    Class['codavox::config'] ~> Service[$service_name]
  }
}
