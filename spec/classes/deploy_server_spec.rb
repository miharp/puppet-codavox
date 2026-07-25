# frozen_string_literal: true

require 'spec_helper'

describe 'codavox::deploy_server' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'with neither credential' do
        let(:pre_condition) do
          "class { 'codavox': staging => '/etc/puppetlabs/code-staging' }"
        end

        # Each credential enables its own route, so with neither the daemon has
        # no reachable endpoint at all. codavox refuses to start; fail earlier.
        it { is_expected.to compile.and_raise_error(%r{deploy_server_api_token_file}) }
      end

      context 'without staging' do
        let(:pre_condition) do
          "class { 'codavox': deploy_server_secret_file => '/etc/codavox/webhook.secret' }"
        end

        it { is_expected.to compile.and_raise_error(%r{codavox::staging}) }
      end

      context 'with a secret file it does not manage' do
        let(:pre_condition) do
          <<~PUPPET
            class { 'codavox':
              staging                   => '/etc/puppetlabs/code-staging',
              deploy_server_secret_file => '/etc/codavox/webhook.secret',
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_service('codavox-deploy-server').with_ensure('running') }

        # The path was named but no contents given, so the file belongs to
        # whoever else manages it.
        it { is_expected.not_to contain_file('/etc/codavox/webhook.secret') }
      end

      context 'with both credentials managed' do
        let(:pre_condition) do
          <<~PUPPET
            class { 'codavox':
              staging                      => '/etc/puppetlabs/code-staging',
              deploy_server_api_token_file => '/etc/codavox/api.token',
              deploy_server_secret_file    => '/etc/codavox/webhook.secret',
              deploy_server_api_token      => Sensitive('a-token'),
              deploy_server_secret         => Sensitive('a-secret'),
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        # 0600, and never diffed into a report: these are the credentials that
        # authorize a deploy.
        it {
          is_expected.to contain_file('/etc/codavox/api.token').
            with_ensure('file').
            with_owner('root').
            with_group('root').
            with_mode('0600').
            with_show_diff(false)
        }

        it { is_expected.to contain_file('/etc/codavox/webhook.secret').with_mode('0600').with_show_diff(false) }

        # Rotating a credential has to restart the daemon; it reads them once at
        # startup.
        it { is_expected.to contain_file('/etc/codavox/api.token').that_notifies('Service[codavox-deploy-server]') }
        it { is_expected.to contain_file('/etc/codavox/webhook.secret').that_notifies('Service[codavox-deploy-server]') }
      end
    end
  end
end
