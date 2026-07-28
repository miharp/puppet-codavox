# frozen_string_literal: true

require 'spec_helper'

describe 'codavox::standalone' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      # Both settings live on the main class, so they cannot be passed from
      # standalone and have to be declared the way an operator would in Hiera.
      let(:configured) do
        <<~PP
          class { 'codavox':
            basedir          => '/etc/puppetlabs/code/environments',
            agent_publisher  => 'https://puppet.example.com:8150',
          }
        PP
      end

      let(:versioned_code) { '/etc/puppetlabs/puppetserver/conf.d/versioned-code.conf' }

      context 'without a publisher' do
        # Pinned, because the suggested URL is built from this node's own
        # certname and would otherwise be whatever the developer's machine is
        # called.
        let(:node) { 'standalone.example.com' }
        let(:pre_condition) do
          "class { 'codavox': basedir => '/etc/puppetlabs/code/environments' }"
        end

        # The message has to name the setting and give a URL built from the
        # certname, because the obvious guess, localhost, cannot verify against
        # the certificate the publisher presents.
        it { is_expected.to compile.and_raise_error(%r{codavox::agent_publisher}) }
        it { is_expected.to compile.and_raise_error(%r{https://standalone\.example\.com:8150}) }
      end

      context 'on a first run, before anything has converged' do
        let(:pre_condition) { configured }

        it { is_expected.to compile.with_all_deps }

        # The point of the class: everything that produces code is running.
        it { is_expected.to contain_class('codavox::publish') }
        it { is_expected.to contain_class('codavox::agent') }

        # And the thing that would brick the node is not. Repointing
        # environmentpath at a directory the agent has not filled stops catalog
        # compilation, and on one node the agent that would fix it needs a
        # catalog from the server it just broke.
        it { is_expected.not_to contain_class('codavox::server') }
        it { is_expected.not_to contain_file(versioned_code) }
        it { is_expected.not_to contain_ini_setting('codavox environmentpath') }

        # Nothing is *removed* either: a node being converted keeps whatever it
        # had until there is something better to point at.
        it { is_expected.to contain_service('codavox-publish').with_ensure('running') }
        it { is_expected.to contain_service('codavox-agent').with_ensure('running') }

        # The publisher has to be up before the agent has anything to poll.
        it { is_expected.to contain_class('codavox::publish').that_comes_before('Class[codavox::agent]') }
      end

      context 'once production has converged' do
        let(:pre_condition) { configured }
        let(:facts) do
          os_facts.merge(codavox_environments: { 'production' => 'a1b2c3d4' })
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('codavox::server') }
        it { is_expected.to contain_file(versioned_code).with_ensure('file') }

        it {
          is_expected.to contain_ini_setting('codavox environmentpath')
            .with_ensure('present')
            .with_value('/opt/puppetlabs/codavox/environments')
        }

        # Static catalogs are the whole reason a single-server estate installs
        # this: the setting already defaults to true but does nothing without a
        # code_id command to go with it.
        it { is_expected.to contain_ini_setting('codavox static_catalogs').with_value(true) }

        it { is_expected.to contain_class('codavox::agent').that_comes_before('Class[codavox::server]') }
      end

      context 'when a different environment has converged' do
        let(:pre_condition) { configured }
        let(:facts) do
          os_facts.merge(codavox_environments: { 'testing' => 'a1b2c3d4' })
        end

        # production is what require_environment names, and it is not there.
        # Wiring on the strength of some other environment would point
        # environmentpath at a directory with no production in it.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('codavox::server') }
      end

      context 'with require_environment naming the converged one' do
        let(:pre_condition) { configured }
        let(:params) { { require_environment: 'testing' } }
        let(:facts) do
          os_facts.merge(codavox_environments: { 'testing' => 'a1b2c3d4' })
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('codavox::server') }
      end

      context 'with an empty fact' do
        let(:pre_condition) { configured }
        let(:facts) { os_facts.merge(codavox_environments: {}) }

        # An agent that has run but converged on nothing is not ready, and must
        # read the same as an agent that has never run.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('codavox::server') }
      end

      context 'with a fact of the wrong shape' do
        let(:pre_condition) { configured }
        let(:facts) { os_facts.merge(codavox_environments: 'production') }

        # Whatever produced this, it is not evidence of convergence. Refusing to
        # wire is the safe reading; failing to compile would be worse, since a
        # broken fact would then take catalogs down with it.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('codavox::server') }
      end

      context 'with manage_server false' do
        let(:pre_condition) { configured }
        let(:params) { { manage_server: false } }
        let(:facts) do
          os_facts.merge(codavox_environments: { 'production' => 'a1b2c3d4' })
        end

        # Converged, but the operator has said not to touch the server: run the
        # publisher and agent and leave compilation where it is.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('codavox::agent') }
        it { is_expected.not_to contain_class('codavox::server') }
      end

      context 'with wait_for_convergence false' do
        let(:pre_condition) { configured }
        let(:params) { { wait_for_convergence: false } }

        # The escape hatch, for restoring a node whose version directories are
        # already in place: wire immediately, without waiting for the fact.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('codavox::server') }
      end

      context 'with server parameters set in Hiera' do
        let(:pre_condition) { configured }
        let(:facts) do
          os_facts.merge(codavox_environments: { 'production' => 'a1b2c3d4' })
        end
        let(:params) { { require_environment: 'production' } }

        # `contain` rather than a resource-like declaration, so codavox::server
        # keeps its own automatic parameter lookup and an operator can still
        # tune it without standalone having to proxy every setting.
        it { is_expected.to contain_class('codavox::server').with_code_id_command('/usr/bin/codavox-code-id') }
      end
    end
  end
end
