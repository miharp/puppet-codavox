# codavox

Manages [codavox](https://github.com/miharp/codavox), which distributes
versioned Puppet code to OpenVox compilers.

## Table of Contents

- [What codavox does, and why it needs a module](#what-codavox-does-and-why-it-needs-a-module)
- [Setup](#setup)
- [Usage](#usage)
  - [A primary that publishes](#a-primary-that-publishes)
  - [A compiler](#a-compiler)
  - [A single primary that serves its own catalogs](#a-single-primary-that-serves-its-own-catalogs)
  - [Replacing a hand-rolled static catalog setup](#replacing-a-hand-rolled-static-catalog-setup)
- [Reference](#reference)
- [Limitations](#limitations)
- [Development](#development)

## What codavox does, and why it needs a module

OpenVox Server can compile **static catalogs**, which inline file metadata so an
agent applies one consistent version of your code. To do that it needs two
commands: one that answers "which version is this environment?" and one that
answers "give me this file, as of that version."

Those commands are usually a pair of shell scripts, and the scripts are usually
wrong in the same two ways. A `code_id` script that falls back to a timestamp
when it cannot find a git signature gives every compile a different version. A
`code_content` script that falls back to reading the file from the current tree
serves content from **a different version than the catalog was compiled
against** — while exiting zero. That is the precise failure static catalogs
exist to prevent, and nothing reports it.

codavox replaces both with commands that have no fallback: an undeployed
`code_id` is a hard error. It distributes resolved code trees addressed by a
content hash, so every compiler can prove which version it is serving, and a
compiler that was down during a deploy catches up on its own next poll.

This module installs it, configures it, and points OpenVox Server at it.

## Setup

codavox publishes rpm and deb packages to GitHub Releases and runs no package
repository, so the usual case is to install from a release URL:

```yaml
codavox::package_source: 'https://github.com/miharp/codavox/releases/download/v0.2.1/codavox_0.2.1_linux_amd64.rpm'
```

Including `codavox` on its own installs the package and writes
`/etc/codavox/config.yaml`. It **starts nothing**: which daemon a node runs is
the node's role, not a consequence of installing software. Add one or more role
classes to make something happen.

## Usage

### A primary that publishes

The publisher seals r10k's staging directory into content-addressed versions and
serves them to compilers over mutual TLS, reusing the Puppet certificate the node
already holds.

```yaml
codavox::staging: '/etc/puppetlabs/code-staging'
codavox::publish_allow_roles:
  - 'openvox_compiler'
```

```puppet
include codavox::publish
```

`publish_allow_roles` is authorization, not decoration. A certificate signed by
your Puppet CA proves only that the peer is *some* enrolled node, and every agent
in your estate clears that bar. Puppet manifests routinely name internal hosts
and credential paths, so the `pp_role` extension is what actually limits who can
fetch the estate's code.

Add the deploy API and webhook on the same node if you want deploys triggered by
CI or a control-repo push:

```puppet
include codavox::deploy_server
```

### A compiler

```yaml
codavox::agent_publisher: 'https://puppet.example.com:8150'
```

```puppet
include codavox::agent
include codavox::server
```

`codavox::agent` polls, fetches, verifies by resealing the unpacked tree, and
swaps the environment symlink. `codavox::server` points OpenVox Server at what it
deployed.

### A single primary that serves its own catalogs

A primary that compiles its own catalogs is also a client of its own publisher,
so **its own role has to appear in `publish_allow_roles`** or it will be refused
by the authorization check it just enabled. ovadm gives a primary
`pp_role: openvox_server`:

```yaml
codavox::staging: '/etc/puppetlabs/code-staging'
codavox::agent_publisher: 'https://puppet.example.com:8150'
codavox::publish_allow_roles:
  - 'openvox_server'      # this node, as a client of its own publisher
  - 'openvox_compiler'    # any real compilers
```

```puppet
include codavox::publish
include codavox::agent
include codavox::server
```

Read [Limitations](#limitations) before doing this on a node that manages itself.

### Replacing a hand-rolled static catalog setup

`codavox::server` is a drop-in replacement for a profile that deploys
`code_id`/`code_content` scripts. Because it can be switched off without being
removed, a control repository can A/B the two:

```puppet
class profile::codavox {
  include codavox::agent
  class { 'codavox::server':
    enabled => lookup('profile::codavox::enabled', Boolean, 'first', true),
  }
}
```

Setting `enabled => false` removes `versioned-code.conf` and the `puppet.conf`
settings again, returning the server to whatever it used before.

## Reference

See [REFERENCE.md](REFERENCE.md), generated from the inline documentation.

## Limitations

**The first cutover on a self-managing primary needs care.** Pointing
`environmentpath` at a directory the agent has not filled yet leaves OpenVox
Server with no environments, and every catalog compile fails — including the run
making the change. `codavox::server` orders itself after `codavox::agent` when
both are included, which narrows the window but does not close it: the agent
converges asynchronously.

On a node that compiles its own catalog, do it in two passes — apply with
`manage_environmentpath => false`, confirm `codavox code-id production` answers,
then remove the override. A future release should replace that advice with a fact
so the module can tell for itself.

**Version pinning with `package_source` is rpm-only.** The `dpkg` provider has no
versionable feature, so on Debian and Ubuntu `package_ensure` must be `installed`,
`present`, `absent`, or `purged` when installing from a file. The module fails with
an explanation rather than quietly ignoring a pin.

**The API token and webhook secret are optional to manage.** Give
`deploy_server_api_token` or `deploy_server_secret` to have the module write them
(0600, never diffed); leave them unset and the named files are assumed to be
managed elsewhere. codavox will not start if a file it is told to read is absent.

**No acceptance tests yet.** The unit tests cover the catalog thoroughly, but the
end-to-end behaviour — a real puppetserver compiling a static catalog against
deployed code — is exercised in
[codavox's own integration harness](https://github.com/miharp/codavox/tree/main/test/integration)
rather than here.

**Not published to the Forge.** There is deliberately no release workflow: it
would fire on any `v*.*.*` tag and try to publish, which is not wanted yet.
Consume it from git meanwhile, pinning a commit so a deploy is reproducible:

```ruby
mod 'codavox',
  git: 'https://github.com/miharp/puppet-codavox',
  ref: '<commit sha>'
```

Publishing later needs a `release.yml` calling
`voxpupuli/gha-puppet/.github/workflows/release.yml`, plus
`PUPPET_FORGE_USERNAME` and `PUPPET_FORGE_API_KEY` in repository secrets. The
module name would move from `miharp-codavox` to whichever namespace it is
published under.

## Development

Use the `Gemfile`. It is what CI resolves from, and the only toolchain whose
verdict means anything:

```console
bundle exec rake validate lint check   # exactly what CI runs
bundle exec rake rubocop
bundle exec rake spec
bundle exec rake strings:generate:reference   # after changing any class doc
```

Without a local Ruby 3.2 — the version CI uses — the same thing in a container:

```console
docker run --rm -v "$PWD":/repo -w /repo ruby:3.2 sh -c \
  'bundle install --quiet && bundle exec rake validate lint check spec'
```

The [voxbox container](https://github.com/voxpupuli/container-voxbox) is quicker
and tempting, but **do not trust it for this module**. It carries its own gems,
currently a major behind this `Gemfile`, and the two disagree in ways that are
worse than a missed warning:

- Its rubocop wants trailing dots in multi-line chains; CI's wants leading dots.
  Running `rubocop -A` in the container produces code CI then rejects.
- Its strings implementation does not document defaults that come from module
  data, so it validates a `REFERENCE.md` that CI considers outdated.

Both cost a red CI run here before the `Gemfile` was corrected from `puppet` to
`openvox`, which is what put the container and CI in different gem families to
begin with.
