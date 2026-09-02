# codavox

Manages [codavox](https://github.com/miharp/codavox), which distributes
versioned Puppet code to OpenVox compilers.

## Table of Contents

- [What codavox does, and why it needs a module](#what-codavox-does-and-why-it-needs-a-module)
- [Setup](#setup)
- [Usage](#usage)
  - [A primary](#a-primary)
  - [A primary that only publishes](#a-primary-that-only-publishes)
  - [A compiler](#a-compiler)
  - [The environment cache](#the-environment-cache)
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

Including `codavox` configures the
[harpworks package repository](https://packages.harpworks.org), installs the
package from it, and writes `/etc/codavox/config.yaml`. Nothing needs setting
for that; pin a version with `codavox::package_ensure: '0.8.0'`, or let
`latest` follow releases. The repository's signing key ships in this module,
so the trust anchor is reviewed like any other change and the first apply needs
no network beyond the package manager's own.

A host that cannot reach the repository can install from a release file or URL
instead, which also leaves the repository unconfigured:

```yaml
codavox::package_source: 'https://github.com/miharp/codavox/releases/download/v0.8.0/codavox_0.8.0_linux_amd64.rpm'
```

The class It **starts nothing**: which daemon a node runs is
the node's role, not a consequence of installing software. Add one or more role
classes to make something happen.

## Usage

### A primary

`codavox::primary` runs the publisher, the agent, and the server wiring on one
node. Use it wherever the node holding the code also compiles catalogs — a single
OpenVox Server with no compilers, or a primary in a compiler estate that wants
versioned catalogs for itself rather than only handing them to everyone else:

```yaml
codavox::basedir: '/etc/puppetlabs/code/environments'
codavox::agent_publisher: "https://%{trusted.certname}:8150"
codavox::publish_allow_roles:
  - 'openvox_compiler'    # any compilers added later
```

```puppet
include codavox::primary
```

This node is a client of its own publisher, but it does **not** need to appear in
`publish_allow_roles`: the publisher always admits its own certname, since that
node already holds the code in plaintext on local disk. The allowlist still has
to name something — an empty one is refused at startup — so name the role your
compilers will carry, even if there are none yet.

The publisher must be named by certname rather than localhost, because it
presents this node's Puppet certificate and localhost would not verify against
it.

The class wires OpenVox Server only once the `codavox_environments` fact reports
the environment converged, so the first run installs and starts codavox while
catalogs keep compiling from the staging tree, and a later run does the cutover.
Nothing needs sequencing by hand — see [Limitations](#limitations) for what that
protects against.

**There is no separate single-node topology.** A primary set up this way works
the same whether it has compilers or not, and adding one later is purely
additive: the new compiler gets `codavox::agent` and `codavox::server` pointed at
this node's publisher, and nothing here changes.

### A primary that only publishes

Where the primary hands code to compilers but compiles no catalogs of its own.
`codavox::primary` above is usually the better choice, since a primary that
manages itself is compiling at least one catalog.

The publisher seals r10k's basedir directory into content-addressed versions and
serves them to compilers over mutual TLS, reusing the Puppet certificate the node
already holds.

```yaml
codavox::basedir: '/etc/puppetlabs/code/environments'
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

If your compilers were enrolled before codavox existed they carry no `pp_role`,
and adding one means re-issuing every certificate. Name them instead, and drop
each from the list as its certificate is re-issued with a role:

```yaml
codavox::publish_allow_certnames:
  - 'compiler01.example.com'
  - 'compiler02.example.com'
```

Either check admits, so the estate can move a node at a time. Matching is exact.

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

### The environment cache

A swap alone is not a deploy. OpenVox Server caches each environment for
`environment_timeout` and never re-reads the symlink while the cache holds, so
after a swap it would keep compiling the old tree while `codavox code-id`
reports the new `code_id` — a catalog stamped with a version that does not
describe it. So after every swap the agent asks the server on its own node to
expire that environment, over
`DELETE /puppet-admin-api/v1/environment-cache`, and the `auth.conf` OpenVox
Server ships denies that path to everyone.

`codavox::server` writes the rule that allows it, admitting this node by its
own certname — the node's agent is the only caller. A refused flush is a
failed sync, reported on every deploy until the rule exists, so keep
`manage_cache_flush_rule` on unless you write the rule some other way.

With the flush in place, holding the cache is safe, and a compiler that does
not re-parse every environment on every catalog compiles faster:

```yaml
codavox::server::environment_timeout: unlimited
```

To share one rule across the fleet instead of one per node, admit the
`pp_role` your compilers carry — by OID, because a compiler runs with its CA
service disabled and the admin API then resolves no extension short names:

```yaml
codavox::server::cache_flush_allow:
  extensions:
    '1.3.6.1.4.1.34380.1.1.13': openvox_compiler
```

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

`codavox::primary` handles this for you. It reads the `codavox_environments`
fact — the same environment symlinks `codavox code-id` reads — and leaves OpenVox
Server alone until the environment has actually converged, so the cutover lands
on a later run with nothing sequenced by hand. Prefer it on any node that
compiles its own catalogs, with or without compilers.

Composing the classes yourself on such a node still means two passes: apply with
`manage_environmentpath => false`, confirm `codavox code-id production` answers,
then remove the override.

**Version pinning with `package_source` is rpm-only.** From the repository a
pin works everywhere, but the `dpkg` provider has no versionable feature, so on
Debian and Ubuntu `package_ensure` must be `installed`, `present`, `absent`, or
`purged` when installing from a file. The module fails with an explanation
rather than quietly ignoring a pin.

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
