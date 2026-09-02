# @summary Configures the harpworks package repository. Private.
#
# One repository serves every tool published under the harpworks name, so a
# node that later adopts a second one adds nothing here. The public key ships
# in this module rather than being fetched at apply time: the trust anchor is
# then pinned in code, reviewed like any other change, and the first apply
# needs no network beyond the package manager's own.
#
# What the repository signs is its metadata, not the packages, which is how
# apt has always worked and what dnf checks with repo_gpgcheck; the packages
# stay byte-for-byte the release assets. See
# https://github.com/miharp/codavox/blob/main/docs/installation.md.
#
# @api private
class codavox::repo {
  assert_private()

  $base = $codavox::repo_baseurl

  case $facts['os']['family'] {
    'RedHat': {
      file { '/etc/pki/rpm-gpg/RPM-GPG-KEY-harpworks':
        ensure => file,
        owner  => 'root',
        group  => 'root',
        mode   => '0644',
        source => 'puppet:///modules/codavox/harpworks.asc',
      }

      yumrepo { 'harpworks':
        descr         => 'harpworks - tools for OpenVox',
        baseurl       => "${base}/rpm",
        enabled       => '1',
        gpgcheck      => '0',
        repo_gpgcheck => '1',
        gpgkey        => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-harpworks',
        require       => File['/etc/pki/rpm-gpg/RPM-GPG-KEY-harpworks'],
      }
    }

    'Debian': {
      file { '/etc/apt/keyrings':
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
      }

      file { '/etc/apt/keyrings/harpworks.asc':
        ensure => file,
        owner  => 'root',
        group  => 'root',
        mode   => '0644',
        source => 'puppet:///modules/codavox/harpworks.asc',
      }

      file { '/etc/apt/sources.list.d/harpworks.list':
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "deb [signed-by=/etc/apt/keyrings/harpworks.asc] ${base}/deb stable main\n",
        require => File['/etc/apt/keyrings/harpworks.asc'],
      }

      # apt knows nothing of a new source until it has read it. Refreshed only
      # when the source or the key changes, so a steady-state run does nothing.
      exec { 'harpworks apt-get update':
        command     => '/usr/bin/apt-get update',
        refreshonly => true,
        subscribe   => File['/etc/apt/sources.list.d/harpworks.list', '/etc/apt/keyrings/harpworks.asc'],
      }
    }

    default: {
      fail("codavox: the harpworks repository has no packages for ${facts['os']['family']}; set codavox::package_source, or codavox::repo_manage to false")
    }
  }
}
