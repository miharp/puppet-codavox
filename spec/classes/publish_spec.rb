# frozen_string_literal: true

require 'spec_helper'

describe 'codavox::publish' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'without staging' do
        # A publisher with no staging directory would come up serving nothing,
        # and every compiler would poll an empty environment list and report
        # success. Refusing to compile is the louder failure.
        it { is_expected.to compile.and_raise_error(%r{codavox::staging}) }
      end

      context 'with staging' do
        let(:pre_condition) do
          "class { 'codavox': staging => '/etc/puppetlabs/code-staging' }"
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_service('codavox-publish')
            .with_ensure('running')
            .with_enable(true)
        }

        it { is_expected.to contain_class('codavox::config').that_notifies('Service[codavox-publish]') }
      end

      context 'alongside the agent on one node' do
        # A primary that serves its own catalogs runs both, and is a client of
        # its own publisher. Both services must coexist in one catalog.
        let(:pre_condition) do
          <<~PUPPET
            class { 'codavox':
              staging             => '/etc/puppetlabs/code-staging',
              agent_publisher     => 'https://puppet.example.com:8150',
              publish_allow_roles => ['openvox_server'],
            }
            include codavox::agent
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_service('codavox-publish') }
        it { is_expected.to contain_service('codavox-agent') }
      end
    end
  end
end
