# @summary Installs the codavox package. Private.
#
# @api private
class codavox::install {
  assert_private()

  if $codavox::package_manage {
    if $codavox::package_source {
      # dpkg cannot pin a version: the provider lacks the versionable feature, so
      # Puppet refuses `ensure => '0.2.1'` outright. Installing from a file makes
      # the pin redundant anyway — the file is the version — but say so rather
      # than quietly installing whatever the file holds while the operator
      # believes a version was pinned.
      $unversionable = ['present', 'installed', 'absent', 'purged']
      if $codavox::package_provider == 'dpkg' and !($codavox::package_ensure in $unversionable) {
        fail("codavox::package_ensure must be one of ${unversionable.join(', ')} when installing from codavox::package_source on Debian: the dpkg provider cannot pin a version, and the source file already determines it") # lint:ignore:140chars
      }

      # A release file or URL. The dependency-resolving providers cannot take
      # one, so the low-level provider for the OS family is used instead. That
      # is safe here only because codavox is a static binary with no
      # dependencies to resolve.
      package { $codavox::package_name:
        ensure   => $codavox::package_ensure,
        source   => $codavox::package_source,
        provider => $codavox::package_provider,
      }
    } else {
      package { $codavox::package_name:
        ensure => $codavox::package_ensure,
      }
    }
  }
}
