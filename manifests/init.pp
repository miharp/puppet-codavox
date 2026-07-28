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
#   A version to pin, or `installed`, `latest`, or `absent`.
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
# @param package_source
#   Install from this file or URL instead of from a repository. codavox publishes
#   to GitHub Releases and runs no package repository, so this is the ordinary
#   case rather than the exception. A direct package install resolves no
#   dependencies; codavox is a static binary and has none.
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
# @param agent_prune_environments
#   Whether to remove environments the publisher no longer serves. Off by
#   default because deletion is destructive; needs r10k's `purge_levels` set to
#   match.
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
#   codavox::package_source: 'https://github.com/miharp/codavox/releases/download/v0.6.2/codavox_0.6.2_linux_amd64.rpm'
#   codavox::basedir: '/etc/puppetlabs/code/environments'
#
class codavox (
  String[1] $package_name,
  String[1] $package_ensure,
  Stdlib::Absolutepath $config_file,
  Stdlib::Absolutepath $environmentpath,
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
  Optional[String[1]] $publish_listen = undef,
  Optional[Array[String[1], 1]] $publish_allow_roles = undef,
  Optional[Array[Stdlib::Host, 1]] $publish_allow_certnames = undef,
  Optional[Enum['chain', 'leaf', 'false']] $publish_certificate_revocation = undef,
  Optional[Stdlib::HTTPUrl] $agent_publisher = undef,
  Optional[String[1]] $agent_interval = undef,
  Optional[Integer[1]] $agent_keep = undef,
  Optional[String[1]] $agent_min_age = undef,
  Optional[Boolean] $agent_prune_environments = undef,
  Optional[String[1]] $deploy_server_listen = undef,
  Optional[Stdlib::Absolutepath] $deploy_server_api_token_file = undef,
  Optional[Stdlib::Absolutepath] $deploy_server_secret_file = undef,
  Optional[Sensitive[String[1]]] $deploy_server_api_token = undef,
  Optional[Sensitive[String[1]]] $deploy_server_secret = undef,
  Optional[Integer[1]] $deploy_server_history = undef,
) {
  contain codavox::install
  contain codavox::config

  # The package ships the configuration file, so it has to land before Puppet
  # writes it or the two contend for the same path. Services are ordered after
  # config by each role class, since not every node runs one.
  Class['codavox::install'] -> Class['codavox::config']
}
