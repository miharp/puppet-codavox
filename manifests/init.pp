# @summary Installs codavox and manages its configuration file.
#
# codavox distributes versioned Puppet code to OpenVox compilers. It implements
# OpenVox Server's already-shipped versioned-code-service contract, so the server
# needs no patching: each compiler answers "which exact version am I serving?"
# from the same symlink the server resolves, which turns divergence between
# compilers from a correctness bug into a latency property.
#
# This class installs the package and writes the configuration file. It starts
# nothing. Which daemon a node runs is decided by including a role class, because
# that belongs to the node's role rather than to the act of installing software:
#
# * `codavox::publish` — serve versioned code to compilers, on the primary
# * `codavox::agent` — converge this compiler onto the publisher
# * `codavox::deploy_server` — the deploy API and control-repo webhook
# * `codavox::server` — point OpenVox Server at codavox, on each compiler
#
# Every setting arrives here. The role classes read these values back rather
# than taking duplicates of their own, so each one has a single source of truth.
#
# @param package_name
#   The package to install.
#
# @param package_ensure
#   A version to pin, such as `'0.8.0'`, or `installed`, `latest`, or `absent`.
#   From the repository a pin works on every supported OS.
#
# @param config_file
#   Path to the configuration file the daemons read.
#
# @param environmentpath
#   The directory codavox owns and fills with environment symlinks, and which
#   OpenVox Server is pointed at. Deliberately not the stock `code/environments`:
#   a fresh OpenVox Server ships a populated directory there, and `rename(2)`
#   cannot replace a real directory with a symlink.
#
# @param repo_manage
#   Whether to configure the harpworks package repository, which serves codavox
#   and every other tool published under that name. On by default; the
#   repository is where releases live. Ignored when `package_source` is set.
#
# @param repo_baseurl
#   Where the repository is served from. Change it only for a mirror.
#
# @param package_source
#   Install from this file or URL instead of from the repository, for a host
#   that cannot reach it. The repository is then not configured. A direct
#   package install resolves no dependencies and cannot be upgraded by the
#   package manager; codavox is a static binary, so the first is harmless.
#
# @param package_provider
#   Provider to use when `package_source` is set. Defaults per OS family from
#   this module's data.
#
# @param package_manage
#   Whether to manage the package. Set to false when something else installs it.
#
# @param config_manage
#   Whether to manage the configuration file. The package ships it as a
#   noreplace conffile with every setting commented out, so an upgrade never
#   overwrites what Puppet writes here.
#
# @param basedir
#   r10k's basedir: the tree the publisher seals. Required by `codavox::publish`
#   and `codavox::deploy_server`, and it must be the same directory r10k deploys
#   into.
#
# @param state
#   Where the publisher keeps materialized artifacts, its pidfile, and the
#   provenance log.
#
# @param ssldir
#   Puppet's ssldir. codavox reuses the certificate the node already holds and
#   issues none of its own, so there is no second PKI to rotate or revoke.
#
# @param certname
#   This node's certname. Left unset, codavox uses the node's hostname.
#
# @param r10k
#   Path to the r10k binary, for `codavox::deploy_server`.
#
# @param r10k_config
#   Path to r10k.yaml, for `codavox::deploy_server`.
#
# @param r10k_timeout
#   Bound on one r10k run, as a Go duration such as `10m`, for
#   `codavox::deploy_server` and `codavox deploy`. Past it, r10k and everything
#   it spawned are terminated and the deploy fails, so a fetch from an
#   unreachable remote cannot hold the deploy lock forever. Left unset, codavox
#   defaults to ten minutes; raise it if a large first deploy over a slow link
#   legitimately needs more.
#
# @param publish_listen
#   Address the publisher listens on.
#
# @param publish_allow_roles
#   The `pp_role` values permitted to fetch code. A certificate signed by the
#   Puppet CA proves only that the peer is *some* enrolled node, and every agent
#   in the estate clears that bar, so the role is what actually authorizes.
#
#   A node that serves its own catalogs is also a client of its own publisher,
#   but does not need listing here: the publisher always admits its own certname,
#   because that node already holds the code in plaintext on local disk. List
#   what your compilers carry — ovadm gives a compiler `openvox_compiler`.
#
# @param publish_allow_certnames
#   Individual compilers permitted to fetch code, matched exactly against the
#   certificate common name.
#
#   This is for an estate that already has compilers. `pp_role` is fixed when a
#   certificate is issued, so a node enrolled before codavox existed cannot be
#   given one without re-issuing its certificate — revoke, clean, re-enrol,
#   restart — for every compiler. Naming them admits them today, and each can be
#   dropped from the list as its certificate is re-issued with a role.
#
#   Either check admits. Setting only this one means no role admits anyone.
#
# @param publish_certificate_revocation
#   Whether the publisher refuses revoked certificates, read from
#   `<ssldir>/crl.pem`. Takes Puppet's own values: `chain`, `leaf`, or `false`.
#   Left unset, codavox defaults to `chain`, as puppetserver does. Set `false`
#   only where no CRL is distributed.
#
# @param agent_publisher
#   The publisher's base URL. Required by `codavox::agent`.
#
# @param agent_interval
#   How often the agent polls, as a Go duration such as `30s`.
#
# @param agent_keep
#   How many superseded versions to retain per environment.
#
# @param agent_min_age
#   How long a superseded version is retained regardless of `agent_keep`. This
#   is the guard that matters: an agent run holding a catalog stamped with an
#   older `code_id` still requests file content for it.
#
# @param agent_max_unpacked
#   Most one artifact may expand to on disk, as a size with an optional K, M,
#   or G suffix such as `2G`. An artifact past it is refused before it lands,
#   so a wrong or compromised publisher cannot fill every compiler's disk with
#   one small file. Left unset, codavox defaults to 2 GiB, far above any Puppet
#   code tree; raise it only for an environment that really carries that much.
#   It cannot be turned off.
#
# @param agent_prune_environments
#   Whether to remove environments the publisher no longer serves. Off by
#   default because deletion is destructive. The primary-side half needs no
#   setting: r10k's default `purge_levels` already removes an environment whose
#   branch is gone, at the end of every deploy. If you override `purge_levels`
#   in r10k.yaml, keep `deployment` in it, or removed environments stay
#   published and there is nothing here to prune.
#
# @param agent_puppetserver
#   The OpenVox Server on this node whose environment cache the agent expires
#   after every swap. Left unset, codavox uses `https://<certname>:8140` — the
#   certname rather than localhost, because the server presents its Puppet
#   certificate and the name has to verify against it.
#
# @param agent_flush_environment_cache
#   Whether the agent expires the environment in this node's OpenVox Server
#   cache after every swap. Left unset, codavox defaults to true. Set false only
#   on a server running with `environment_timeout = 0`, which re-reads the
#   environment on every compile and has nothing to expire. `codavox::server`
#   writes the `auth.conf` rule the flush needs.
#
# @param deploy_server_listen
#   Address the deploy server listens on.
#
# @param deploy_server_api_token_file
#   File holding the deploy API bearer token. Setting it enables the API.
#
# @param deploy_server_secret_file
#   File holding the webhook shared secret. Setting it enables the webhook.
#
# @param deploy_server_api_token
#   Contents for `deploy_server_api_token_file`. Left unset, the file is assumed
#   to be managed elsewhere; codavox will not start if it names a file that does
#   not exist.
#
# @param deploy_server_secret
#   Contents for `deploy_server_secret_file`, on the same terms.
#
# @param deploy_server_history
#   How many past deploys to keep in the queryable history.
#
# @example Install the package and write the config, start nothing
#   include codavox
#
# @example A primary that publishes, driven from Hiera
#   codavox::package_ensure: '0.8.0'
#   codavox::basedir: '/etc/puppetlabs/code/environments'
#
class codavox (
  String[1] $package_name,
  String[1] $package_ensure,
  Stdlib::Absolutepath $config_file,
  Stdlib::Absolutepath $environmentpath,
  Boolean $repo_manage = true,
  Stdlib::HTTPUrl $repo_baseurl = 'https://packages.harpworks.org',
  Optional[String[1]] $package_source = undef,
  Optional[String[1]] $package_provider = undef,
  Boolean $package_manage = true,
  Boolean $config_manage = true,
  Optional[Stdlib::Absolutepath] $basedir = undef,
  Optional[Stdlib::Absolutepath] $state = undef,
  Optional[Stdlib::Absolutepath] $ssldir = undef,
  Optional[Stdlib::Host] $certname = undef,
  Optional[Stdlib::Absolutepath] $r10k = undef,
  Optional[Stdlib::Absolutepath] $r10k_config = undef,
  Optional[String[1]] $r10k_timeout = undef,
  Optional[String[1]] $publish_listen = undef,
  Optional[Array[String[1], 1]] $publish_allow_roles = undef,
  Optional[Array[Stdlib::Host, 1]] $publish_allow_certnames = undef,
  Optional[Enum['chain', 'leaf', 'false']] $publish_certificate_revocation = undef,
  Optional[Stdlib::HTTPUrl] $agent_publisher = undef,
  Optional[String[1]] $agent_interval = undef,
  Optional[Integer[1]] $agent_keep = undef,
  Optional[String[1]] $agent_min_age = undef,
  Optional[String[1]] $agent_max_unpacked = undef,
  Optional[Boolean] $agent_prune_environments = undef,
  Optional[Stdlib::HTTPUrl] $agent_puppetserver = undef,
  Optional[Boolean] $agent_flush_environment_cache = undef,
  Optional[String[1]] $deploy_server_listen = undef,
  Optional[Stdlib::Absolutepath] $deploy_server_api_token_file = undef,
  Optional[Stdlib::Absolutepath] $deploy_server_secret_file = undef,
  Optional[Sensitive[String[1]]] $deploy_server_api_token = undef,
  Optional[Sensitive[String[1]]] $deploy_server_secret = undef,
  Optional[Integer[1]] $deploy_server_history = undef,
) {
  if $package_manage and $repo_manage and !$package_source {
    contain codavox::repo
    Class['codavox::repo'] -> Class['codavox::install']
  }
  contain codavox::install
  contain codavox::config

  # The package ships the configuration file, so it has to land before Puppet
  # writes it or the two contend for the same path. Services are ordered after
  # config by each role class, since not every node runs one.
  Class['codavox::install'] -> Class['codavox::config']
}
