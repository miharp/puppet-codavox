# frozen_string_literal: true

require 'spec_helper'

describe 'codavox::server' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      versioned_code = '/etc/puppetlabs/puppetserver/conf.d/versioned-code.conf'
      puppet_conf = '/etc/puppetlabs/puppet/puppet.conf'

      context 'with default parameters' do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('codavox') }

        it { is_expected.to contain_file(versioned_code).with_ensure('file').with_mode('0644') }

        # Both commands or neither: OpenVox Server's validate-config! throws at
        # startup when exactly one is present.
        it { is_expected.to contain_file(versioned_code).with_content(%r{code-id-command: /usr/bin/codavox-code-id}) }
        it { is_expected.to contain_file(versioned_code).with_content(%r{code-content-command: /usr/bin/codavox-code-content}) }

        it {
          is_expected.to contain_ini_setting('codavox static_catalogs').
            with_ensure('present').
            with_path(puppet_conf).
            with_section('server').
            with_setting('static_catalogs').
            with_value(true)
        }

        # environmentpath goes in [main]: a compiler resolves environments
        # through the same setting its own agent side uses.
        it {
          is_expected.to contain_ini_setting('codavox environmentpath').
            with_ensure('present').
            with_section('main').
            with_value('/opt/puppetlabs/codavox/environments')
        }

        # Any of these changing has to restart the server, or it keeps serving
        # from the old wiring.
        it { is_expected.to contain_file(versioned_code).that_notifies('Service[puppetserver]') }
        it { is_expected.to contain_ini_setting('codavox environmentpath').that_notifies('Service[puppetserver]') }
      end

      context 'with enabled false' do
        let(:params) { { enabled: false } }

        # Flipping back must remove the wiring rather than leave it in place, so
        # a control repository can A/B against whatever it used before without
        # deleting code.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file(versioned_code).with_ensure('absent') }
        it { is_expected.to contain_ini_setting('codavox static_catalogs').with_ensure('absent') }
        it { is_expected.to contain_ini_setting('codavox environmentpath').with_ensure('absent') }
      end

      context 'with manage_environmentpath false' do
        let(:params) { { manage_environmentpath: false } }

        # The staged cutover: the commands are wired, but the server keeps
        # serving the code it already has until the agent has converged.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file(versioned_code).with_ensure('file') }
        it { is_expected.not_to contain_ini_setting('codavox environmentpath') }
      end

      context 'with manage_static_catalogs false' do
        let(:params) { { manage_static_catalogs: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_ini_setting('codavox static_catalogs') }
      end

      context 'with service_manage false and nothing else managing the service' do
        let(:params) { { service_manage: false } }

        # The collector forms no relationship when the service is not declared,
        # so this still compiles rather than failing on a missing resource.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_service('puppetserver') }
      end

      context 'with service_manage false and the service declared elsewhere' do
        let(:params) { { service_manage: false } }
        let(:pre_condition) { "service { 'puppetserver': ensure => running, enable => true }" }

        # This is the shape to use where another class owns the service: no
        # duplicate declaration, and the restart still happens.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_file(versioned_code).that_notifies('Service[puppetserver]') }
      end

      context 'with service_manage true and an identical declaration elsewhere' do
        let(:pre_condition) { "service { 'puppetserver': ensure => running, enable => true }" }

        # ensure_resource skips a declaration that already matches. A *differing*
        # one is a duplicate-declaration error, which is why service_manage
        # exists -- see the class documentation.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_service('puppetserver') }
      end

      context 'alongside the agent' do
        let(:pre_condition) do
          <<~PUPPET
            class { 'codavox': agent_publisher => 'https://puppet.example.com:8150' }
            include codavox::agent
          PUPPET
        end

        # Repointing environmentpath before the agent has deployed anything
        # leaves the server with no environments at all, so get the agent
        # started first. This narrows the first-run window; it does not close it.
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('codavox::agent').that_comes_before('Class[codavox::server]') }
      end
    end
  end
end
