# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the module is in 0.x, a minor version may carry breaking changes.

Releases before 0.6.1 were git tags only; the module has been on the
[Forge](https://forge.puppet.com/modules/miharp/codavox) since 0.6.1.

## [Unreleased]

## [0.6.3] - 2026-09-21

### Added

- This changelog, so the Forge page has a Changelog tab.

### Fixed

- `project_page` in `metadata.json` pointed at codavox itself rather than this
  module, so the Forge page's "Project URL" led away from the module's
  repository.

## [0.6.2] - 2026-09-21

### Changed

- `metadata.json` requires `openvox` rather than `puppet`. The Forge turned the
  `puppet` requirement into a list of compatible Puppet Enterprise versions,
  which is wrong for this module: it is for open-source OpenVox Server, and PE
  has Code Manager and file sync for the same job. The README's Limitations
  say so too.

## [0.6.1] - 2026-09-21

First release on the Puppet Forge.

### Added

- A `Release` workflow: pushing a `vX.Y.Z` tag checks it against
  `metadata.json`, then publishes to the Forge and creates the GitHub release
  through Vox Pupuli's shared release workflow. It replaces the verify-only
  `Tag` workflow.
- Forge install instructions and badges in the README.

### Fixed

- The README's link to `REFERENCE.md` is absolute, since the Forge renders the
  README on its own.

## [0.6.0] - 2026-09-02

### Changed

- codavox is installed from the
  [harpworks package repository](https://packages.harpworks.org) by default,
  so upgrades are the package manager's and a version pin works on every
  platform. The repository's signing key ships in the module rather than being
  fetched at apply time. `repo_manage` and `repo_baseurl` control it.
- `package_source` remains for hosts that cannot reach the repository, and
  leaves the repository unconfigured.
- `puppetlabs/yumrepo_core` is a dependency, since `yumrepo` is no longer in
  Puppet core.

## [0.5.0] - 2026-09-02

### Added

- `r10k_timeout` and `agent_max_unpacked`, passing through the limits
  codavox 0.8 introduces. Both are written only when set, so codavox's own
  defaults stay in force.

### Fixed

- The `agent_prune_environments` documentation no longer says r10k's
  `purge_levels` must be set to match. It need not be, and narrowing it would
  have turned off the purge that pruning relies on.

## [0.4.0] - 2026-08-28

### Added

- `codavox::server` writes the `auth.conf` rule that lets the codavox agent
  expire OpenVox Server's environment cache after a swap, which codavox 0.7 and
  later require. It admits the node's own certname by default;
  `cache_flush_allow` shares one rule across a fleet by `pp_role`, and
  `manage_cache_flush_rule` turns it off. The rule is removed with
  `enabled => false`.
- `codavox::server::environment_timeout`, safe to raise now that the cache is
  flushed on every deploy.
- `agent_puppetserver` and `agent_flush_environment_cache` on the main class.
- `puppetlabs/puppet_authorization` is a dependency.

### Fixed

- The `package_source` example is corrected in the docstring it is generated
  from, so regenerating `REFERENCE.md` no longer reverts it.

## [0.3.0] - 2026-07-28

### Added

- `codavox::primary`: the publisher, the agent and the server wiring on one
  node, for any node that both holds the code and compiles catalogs. It wires
  OpenVox Server only once the environment has converged, so a self-managing
  node cannot lock itself out on the first run.
- The `codavox_environments` fact, read from the same environment symlinks
  `codavox code-id` reads, which is what `codavox::primary` waits on.

### Fixed

- The documentation no longer claims a self-compiling node must list its own
  `pp_role` in `publish_allow_roles`; the publisher always admits its own
  certname.

## [0.2.0] - 2026-07-26

### Changed

- **Breaking:** `codavox::staging` is renamed `codavox::basedir`, matching
  codavox 0.5.0, which renamed the setting with no alias. Rename it in Hiera
  when upgrading codavox. Example paths move to
  `/etc/puppetlabs/code/environments`, r10k's own basedir.

### Added

- A `Tag` workflow that refuses a tag whose version disagrees with
  `metadata.json`.

## [0.1.0] - 2026-07-25

### Added

- Initial module: installs and configures codavox, with opt-in role classes
  that start nothing by default — `codavox::publish`, `codavox::agent`,
  `codavox::deploy_server`, and `codavox::server`, which points OpenVox Server
  at codavox and can be switched off without being removed.
- `publish_allow_certnames`, to admit compilers by name while their
  certificates carry no `pp_role`.

[Unreleased]: https://github.com/miharp/puppet-codavox/compare/v0.6.3...HEAD
[0.6.3]: https://github.com/miharp/puppet-codavox/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/miharp/puppet-codavox/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/miharp/puppet-codavox/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/miharp/puppet-codavox/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/miharp/puppet-codavox/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/miharp/puppet-codavox/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/miharp/puppet-codavox/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/miharp/puppet-codavox/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/miharp/puppet-codavox/releases/tag/v0.1.0
