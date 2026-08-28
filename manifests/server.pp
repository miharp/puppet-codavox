# @summary Points OpenVox Server at codavox, enabling correct static catalogs.
#
# Include this on each compiler, alongside `codavox::agent`. It writes
# `versioned-code.conf` naming codavox's two commands, turns static catalogs on,
# points `environmentpath` at the directory codavox fills with symlinks, and
# lets the agent expire this server's environment cache after every deploy.
#
# This is what replaces a hand-rolled pair of shell scripts. The difference is
# not tidiness. A script that answers `code_id` from a timestamp when it cannot
# find a git signature gives every compile a new version, and one that answers
# `code_content` by reading the file from the current tree when it cannot find
# the requested commit serves content from a *different version than the catalog
# was compiled against* while exiting zero. That is the exact failure static
# catalogs exist to prevent, and it is silent. codavox has no such fallback: an
# undeployed `code_id` is a hard error.
#
# ## Ordering on a first run
#
# Repointing `environmentpath` at a directory the agent has not filled yet leaves
# OpenVox Server with no environments, and **every catalog compile fails** —
# including the run making this change, on a primary that manages itself.
#
# This class orders itself after `codavox::agent` when both are included, so the
# agent is installed and started first. That narrows the window but does not close
# it: the agent converges asynchronously, so a first run can still repoint the
# server before the first environment lands. On a node that compiles its own
# catalog, do the cutover in two steps — apply with `enabled => false`, confirm
# `codavox code-id production` answers, then set it true.
#
# @param enabled
#   Whether OpenVox Server is pointed at codavox. Setting this false removes the
#   settings again, so a control repository can flip between codavox and whatever
#   it used before without deleting code.
#
# @param code_id_command
#   Path to the `code_id` command. The package ships this as a symlink, because
#   OpenVox Server passes only positional arguments and so cannot invoke
#   `codavox code-id <env>`.
#
# @param code_content_command
#   Path to the `code_content` command, on the same terms.
#
# @param manage_environmentpath
#   Whether to set `environmentpath`. Leave this false to stage a cutover: the
#   commands are wired but the server keeps serving its existing code.
#
# @param manage_static_catalogs
#   Whether to set `static_catalogs`. It defaults to true in OpenVox Server, so
#   this is usually already the case.
#
# @param manage_cache_flush_rule
#   Whether to write the `auth.conf` rule that lets the agent expire this
#   server's environment cache. After every swap the agent sends
#   `DELETE /puppet-admin-api/v1/environment-cache?environment=<env>` to the
#   server on its own node, and the `auth.conf` OpenVox Server ships denies
#   that path to everyone. Without the rule the server keeps compiling the
#   tree it already parsed while `code-id` reports the new `code_id` — a
#   catalog stamped with a version that does not describe it — and the agent
#   reports every deploy as `sync failed` until the rule exists.
#
# @param cache_flush_allow
#   Who the rule admits, in `auth.conf`'s own `allow` syntax. Left unset, it
#   admits this node by certname, because this node's agent is the only caller
#   the rule is for. To share one rule across the fleet instead, admit the
#   `pp_role` compilers carry — by OID, not by name, because a compiler runs
#   with its CA service disabled and the admin API then resolves no short
#   names:
#
#   ```puppet
#   cache_flush_allow => { 'extensions' => { '1.3.6.1.4.1.34380.1.1.13' => 'openvox_compiler' } }
#   ```
#
# @param auth_conf
#   Path to OpenVox Server's `auth.conf`.
#
# @param environment_timeout
#   Sets `environment_timeout` in `puppet.conf`'s `[server]` section. Left
#   unset, the setting is not managed. A production compiler wants `unlimited`
#   so it does not re-parse every environment on every catalog; the cache flush
#   above is what makes that safe, since it is otherwise only the timeout that
#   ever makes a deploy visible to the server.
#
# @param puppet_config
#   Path to puppet.conf.
#
# @param puppetserver_confdir
#   Directory holding OpenVox Server's HOCON configuration.
#
# @param service_name
#   The OpenVox Server service to restart when the wiring changes.
#
# @param service_manage
#   Whether to declare that service here. Set this false where another class
#   already manages it with attributes of its own, which would otherwise be a
#   duplicate declaration.
#
#   The restart is wired through a resource collector either way, so it happens
#   whenever the service is declared — here or elsewhere — and is skipped
#   silently when nothing manages it at all.
#
# @example Wire it up, with everything else in Hiera
#   include codavox::agent
#   include codavox::server
#
# @example Stage the cutover on a self-compiling primary
#   class { 'codavox::server':
#     manage_environmentpath => false,
#   }
#
class codavox::server (
  Boolean $enabled = true,
  Stdlib::Absolutepath $code_id_command = '/usr/bin/codavox-code-id',
  Stdlib::Absolutepath $code_content_command = '/usr/bin/codavox-code-content',
  Boolean $manage_environmentpath = true,
  Boolean $manage_static_catalogs = true,
  Boolean $manage_cache_flush_rule = true,
  Optional[Variant[Array[Variant[String[1], Hash], 1], Hash]] $cache_flush_allow = undef,
  Stdlib::Absolutepath $puppet_config = '/etc/puppetlabs/puppet/puppet.conf',
  Stdlib::Absolutepath $puppetserver_confdir = '/etc/puppetlabs/puppetserver/conf.d',
  Stdlib::Absolutepath $auth_conf = '/etc/puppetlabs/puppetserver/conf.d/auth.conf',
  Optional[String[1]] $environment_timeout = undef,
  String[1] $service_name = 'puppetserver',
  Boolean $service_manage = true,
) {
  include codavox

  # ensure_resource tolerates an identical declaration elsewhere but not a
  # differing one, so this is not blanket protection: on a node where something
  # else manages the service with other attributes, set service_manage to false
  # and the relationships below notify it through a collector instead.
  if $service_manage {
    ensure_resource('service', $service_name, {
      'ensure' => 'running',
      'enable' => true,
    })
  }

  # Both commands must be set or neither. OpenVox Server's validate-config!
  # throws at startup when exactly one is present, so writing the file as a unit
  # is the only safe shape.
  $conf_ensure = $enabled ? {
    true    => 'file',
    default => 'absent',
  }

  file { "${puppetserver_confdir}/versioned-code.conf":
    ensure  => $conf_ensure,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp("${module_name}/versioned-code.conf.epp", {
      'code_id_command'      => $code_id_command,
      'code_content_command' => $code_content_command,
    }),
  }

  $setting_ensure = $enabled ? {
    true    => 'present',
    default => 'absent',
  }

  if $manage_static_catalogs {
    ini_setting { 'codavox static_catalogs':
      ensure  => $setting_ensure,
      path    => $puppet_config,
      section => 'server',
      setting => 'static_catalogs',
      value   => true,
    }
  }

  if $manage_environmentpath {
    # [main], not [server]: the agent side of a compiler resolves environments
    # through the same setting.
    ini_setting { 'codavox environmentpath':
      ensure  => $setting_ensure,
      path    => $puppet_config,
      section => 'main',
      setting => 'environmentpath',
      value   => $codavox::environmentpath,
    }
  }

  if $environment_timeout {
    ini_setting { 'codavox environment_timeout':
      ensure  => $setting_ensure,
      path    => $puppet_config,
      section => 'server',
      setting => 'environment_timeout',
      value   => $environment_timeout,
    }
  }

  if $manage_cache_flush_rule {
    # This node's own certname unless told otherwise: the agent presents this
    # node's certificate, and nothing else ever calls the endpoint. The name is
    # fixed so the rule can be found and removed again.
    $allow = $cache_flush_allow ? {
      undef   => [$trusted['certname']],
      default => $cache_flush_allow,
    }

    puppet_authorization::rule { 'codavox environment cache flush':
      ensure               => $setting_ensure,
      path                 => $auth_conf,
      match_request_path   => '/puppet-admin-api/v1/environment-cache',
      match_request_type   => 'path',
      match_request_method => 'delete',
      allow                => $allow,
      sort_order           => 200,
    }
  }

  # Restart the server when the wiring changes, or it goes on serving from the
  # configuration it read at startup.
  #
  # A collector rather than a direct reference: it forms the relationship only
  # for a service that is actually declared, so this works whether the service
  # is declared here, declared by another class, or not managed at all — instead
  # of failing to compile in the last case.
  File["${puppetserver_confdir}/versioned-code.conf"] ~> Service<| title == $service_name |>

  if $manage_static_catalogs {
    Ini_setting['codavox static_catalogs'] ~> Service<| title == $service_name |>
  }
  if $manage_environmentpath {
    Ini_setting['codavox environmentpath'] ~> Service<| title == $service_name |>
  }
  if $environment_timeout {
    Ini_setting['codavox environment_timeout'] ~> Service<| title == $service_name |>
  }
  if $manage_cache_flush_rule {
    # auth.conf is read at startup, so the rule needs the same restart.
    Puppet_authorization::Rule['codavox environment cache flush'] ~> Service<| title == $service_name |>
  }

  # Narrow the first-run window described above: if this node also runs the
  # agent, get it installed and started before the server is repointed.
  if defined(Class['codavox::agent']) {
    Class['codavox::agent'] -> Class['codavox::server']
  }
}
