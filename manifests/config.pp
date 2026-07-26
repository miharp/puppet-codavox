# @summary Writes codavox's configuration file. Private.
#
# The file is generated from the parameters on the main class rather than from a
# template an operator can override, so there is one source of truth for every
# setting and no way to smuggle an unmanaged value in behind it.
#
# Only settings that were actually given are written. codavox rejects unknown
# keys outright — a typo is a startup error rather than a silently ignored
# setting — so emitting a key for every parameter, set or not, would turn any
# future rename into a fleet-wide failure to start.
#
# @api private
class codavox::config {
  assert_private()

  if $codavox::config_manage {
    $shared = {
      'basedir'         => $codavox::basedir,
      'state'           => $codavox::state,
      'ssldir'          => $codavox::ssldir,
      'certname'        => $codavox::certname,
      'environmentpath' => $codavox::environmentpath,
      'r10k'            => $codavox::r10k,
      'r10k_config'     => $codavox::r10k_config,
    }

    $publish = {
      'listen'                 => $codavox::publish_listen,
      'allow_roles'            => $codavox::publish_allow_roles,
      'allow_certnames'        => $codavox::publish_allow_certnames,
      'certificate_revocation' => $codavox::publish_certificate_revocation,
    }

    $agent = {
      'publisher'          => $codavox::agent_publisher,
      'interval'           => $codavox::agent_interval,
      'keep'               => $codavox::agent_keep,
      'min_age'            => $codavox::agent_min_age,
      'prune_environments' => $codavox::agent_prune_environments,
    }

    $deploy_server = {
      'listen'    => $codavox::deploy_server_listen,
      'api_token' => $codavox::deploy_server_api_token_file,
      'secret'    => $codavox::deploy_server_secret_file,
      'history'   => $codavox::deploy_server_history,
    }

    # A section with nothing set is dropped entirely, so the file never carries
    # an empty `agent:` key on a node that runs no agent.
    $sections = {
      'publish'       => $publish.filter |$_k, $v| { $v =~ NotUndef },
      'agent'         => $agent.filter |$_k, $v| { $v =~ NotUndef },
      'deploy_server' => $deploy_server.filter |$_k, $v| { $v =~ NotUndef },
    }.filter |$_k, $v| { !$v.empty }

    $settings = $shared.filter |$_k, $v| { $v =~ NotUndef } + $sections

    $header = [
      '# Managed by Puppet. Local edits are overwritten.',
      '#',
      '# codavox rejects unknown keys, so a stray setting here stops the daemons',
      '# rather than being quietly ignored. See codavox::* in Hiera to change it.',
      '',
    ].join("\n")

    file { dirname($codavox::config_file):
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }

    # 0640 root:root, matching what the package ships. The daemons run as root,
    # and the file names the paths to the API token and webhook secret.
    file { $codavox::config_file:
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0640',
      content => "${header}${stdlib::to_yaml($settings)}",
      require => File[dirname($codavox::config_file)],
    }
  }
}
