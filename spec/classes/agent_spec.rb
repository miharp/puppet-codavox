# frozen_string_literal: true

require 'spec_helper'

describe 'codavox::agent' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'without a publisher' do
        # Starting an agent that cannot know where to poll would leave a
        # compiler serving whatever it already had, silently, so refuse to
        # compile instead.
        it { is_expected.to compile.and_raise_error(%r{codavox::agent_publisher}) }
      end

      context 'with a publisher' do
        let(:pre_condition) do
          "class { 'codavox': agent_publisher => 'https://puppet.example.com:8150' }"
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('codavox') }

        it {
          is_expected.to contain_service('codavox-agent')
            .with_ensure('running')
            .with_enable(true)
        }

        # A configuration change has to restart the daemon, or the node keeps
        # polling the old publisher until something else happens to restart it.
        it { is_expected.to contain_class('codavox::config').that_notifies('Service[codavox-agent]') }

        it { is_expected.to contain_package('codavox').that_comes_before('Class[codavox::config]') }
      end

      context 'with service_manage false' do
        let(:pre_condition) do
          "class { 'codavox': agent_publisher => 'https://puppet.example.com:8150' }"
        end
        let(:params) { { service_manage: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_service('codavox-agent') }
        # The package and config are still wanted; only the service is left alone.
        it { is_expected.to contain_file('/etc/codavox/config.yaml') }
      end

      context 'with the service stopped' do
        let(:pre_condition) do
          "class { 'codavox': agent_publisher => 'https://puppet.example.com:8150' }"
        end
        let(:params) { { service_ensure: 'stopped', service_enable: false } }

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_service('codavox-agent')
            .with_ensure('stopped')
            .with_enable(false)
        }
      end
    end
  end
end
