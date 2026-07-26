# @summary Runs the codavox deploy server: the deploy API and control-repo webhook.
#
# Include this on the primary, alongside `codavox::publish`. It gives two front
# doors onto one deploy queue: a token-authenticated API for CI, and a
# secret-authenticated webhook for a push from GitHub, GitLab, or a generic
# caller. However a deploy is triggered it takes the same path and lands in the
# same history.
#
# Unlike the publisher, its callers cannot present a Puppet certificate, so it
# authenticates a bearer token or a shared secret instead of mutual TLS. At least
# one of `codavox::deploy_server_api_token_file` or
# `codavox::deploy_server_secret_file` must be set; each enables its own route,
# and codavox refuses to start with neither.
#
# The token and secret files can be managed here by setting
# `codavox::deploy_server_api_token` and `codavox::deploy_server_secret` — in a
# control repository those come from eyaml. Left unset, the files are assumed to
# be managed elsewhere.
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
# @example Webhook only, with the secret from eyaml
#   codavox::deploy_server_secret_file: '/etc/codavox/webhook.secret'
#   codavox::deploy_server_secret: >
#     ENC[PKCS7,...]
#
class codavox::deploy_server (
  String[1] $service_name = 'codavox-deploy-server',
  Stdlib::Ensure::Service $service_ensure = 'running',
  Boolean $service_enable = true,
  Boolean $service_manage = true,
) {
  include codavox

  if !$codavox::basedir {
    fail('codavox::deploy_server needs codavox::basedir set to r10k\'s basedir')
  }

  if !$codavox::deploy_server_api_token_file and !$codavox::deploy_server_secret_file {
    fail('codavox::deploy_server needs codavox::deploy_server_api_token_file, codavox::deploy_server_secret_file, or both — each enables its own route') # lint:ignore:140chars
  }

  # Only written when the contents were supplied. A file named but not managed
  # here is the operator's, and codavox will not start if it is missing.
  $credentials = {
    $codavox::deploy_server_api_token_file => $codavox::deploy_server_api_token,
    $codavox::deploy_server_secret_file    => $codavox::deploy_server_secret,
  }.filter |$path, $secret| { $path =~ NotUndef and $secret =~ NotUndef }

  $credentials.each |$path, $secret| {
    file { $path:
      ensure    => file,
      owner     => 'root',
      group     => 'root',
      mode      => '0600',
      content   => $secret,
      show_diff => false,
    }
  }

  if $service_manage {
    service { $service_name:
      ensure => $service_ensure,
      enable => $service_enable,
    }

    Class['codavox::config'] ~> Service[$service_name]

    $credentials.each |$path, $_secret| {
      File[$path] ~> Service[$service_name]
    }
  }
}
