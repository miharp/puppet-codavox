# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

describe 'codavox' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      # The generated file is parsed as YAML rather than matched as a string, so
      # these tests assert what codavox will actually read and not how the
      # template happens to lay it out.
      # Named to avoid colliding with rspec-puppet's own `config`, which its
      # adapter calls while setting Puppet's settings up.
      def written_config(catalogue)
        YAML.safe_load(catalogue.resource('file', '/etc/codavox/config.yaml')[:content])
      end

      context 'with default parameters' do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('codavox::install') }
        it { is_expected.to contain_class('codavox::config') }

        # Installing must never start a daemon: which role a node plays is the
        # role's decision, so installing the package changes no behaviour.
        it { is_expected.not_to contain_service('codavox-agent') }
        it { is_expected.not_to contain_service('codavox-publish') }
        it { is_expected.not_to contain_service('codavox-deploy-server') }

        it { is_expected.to contain_package('codavox').with_ensure('installed') }

        it {
          is_expected.to contain_file('/etc/codavox/config.yaml')
            .with_ensure('file')
            .with_owner('root')
            .with_group('root')
            .with_mode('0640')
        }

        # Unset settings are omitted entirely. codavox rejects unknown keys, and
        # writing a key for every parameter would make any future rename a
        # fleet-wide failure to start.
        it 'writes only what was set' do
          expect(written_config(catalogue)).to eq(
            'environmentpath' => '/opt/puppetlabs/codavox/environments',
          )
        end

        it 'writes no empty role sections' do
          expect(written_config(catalogue).keys).not_to include('publish', 'agent', 'deploy_server')
        end
      end

      # Stays a plain local because it selects which examples get defined below,
      # and a let only resolves once an example is already running.
      debian = os_facts[:os]['family'] == 'Debian'

      context 'with a package source, unversioned' do
        # The provider comes from module data per OS family, because the
        # dependency-resolving providers cannot install from a bare file. Read
        # back out of facts rather than closed over, so nothing leaks in.
        let(:expected_provider) { (facts[:os]['family'] == 'Debian') ? 'dpkg' : 'rpm' }
        let(:package_extension) { (facts[:os]['family'] == 'Debian') ? 'deb' : 'rpm' }
        let(:params) do
          {
            package_source: "https://example.com/codavox_0.2.1_linux_amd64.#{package_extension}",
            package_ensure: 'installed',
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_package('codavox')
            .with_ensure('installed')
            .with_source(%r{codavox_0\.2\.1_linux_amd64})
            .with_provider(expected_provider)
        }
      end

      context 'with a package source and a pinned version' do
        let(:params) do
          {
            package_source: 'https://example.com/codavox_0.2.1_linux_amd64.pkg',
            package_ensure: '0.2.1',
          }
        end

        if debian
          # dpkg has no versionable feature, so Puppet cannot honour the pin.
          # Failing is the point: installing whatever the file holds while the
          # operator believes a version was pinned is the kind of quiet
          # substitution codavox itself refuses to make.
          it { is_expected.to compile.and_raise_error(%r{dpkg provider cannot pin a version}) }
        else
          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_package('codavox').with_ensure('0.2.1') }
        end
      end

      context 'with package_manage false' do
        let(:params) { { package_manage: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_package('codavox') }
        it { is_expected.to contain_file('/etc/codavox/config.yaml') }
      end

      context 'with config_manage false' do
        let(:params) { { config_manage: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_file('/etc/codavox/config.yaml') }
      end

      context 'with every section populated' do
        let(:params) do
          {
            staging: '/etc/puppetlabs/code-staging',
            state: '/opt/puppetlabs/codavox/state',
            ssldir: '/etc/puppetlabs/puppet/ssl',
            certname: 'puppet.example.com',
            r10k: '/opt/puppetlabs/puppet/bin/r10k',
            r10k_config: '/etc/puppetlabs/r10k/r10k.yaml',
            publish_listen: ':8150',
            publish_allow_roles: %w[openvox_compiler openvox_server],
            publish_allow_certnames: %w[legacy01.example.com legacy02.example.com],
            publish_certificate_revocation: 'chain',
            agent_publisher: 'https://puppet.example.com:8150',
            agent_interval: '30s',
            agent_keep: 3,
            agent_min_age: '2h',
            agent_prune_environments: false,
            deploy_server_listen: ':8170',
            deploy_server_api_token_file: '/etc/codavox/api.token',
            deploy_server_secret_file: '/etc/codavox/webhook.secret',
            deploy_server_history: 100,
          }
        end

        it { is_expected.to compile.with_all_deps }

        it 'nests each role section under its own key' do
          expect(written_config(catalogue)).to eq(
            'staging' => '/etc/puppetlabs/code-staging',
            'state' => '/opt/puppetlabs/codavox/state',
            'ssldir' => '/etc/puppetlabs/puppet/ssl',
            'certname' => 'puppet.example.com',
            'environmentpath' => '/opt/puppetlabs/codavox/environments',
            'r10k' => '/opt/puppetlabs/puppet/bin/r10k',
            'r10k_config' => '/etc/puppetlabs/r10k/r10k.yaml',
            'publish' => {
              'listen' => ':8150',
              'allow_roles' => %w[openvox_compiler openvox_server],
              'allow_certnames' => %w[legacy01.example.com legacy02.example.com],
              'certificate_revocation' => 'chain',
            },
            'agent' => {
              'publisher' => 'https://puppet.example.com:8150',
              'interval' => '30s',
              'keep' => 3,
              'min_age' => '2h',
              'prune_environments' => false,
            },
            'deploy_server' => {
              'listen' => ':8170',
              'api_token' => '/etc/codavox/api.token',
              'secret' => '/etc/codavox/webhook.secret',
              'history' => 100,
            },
          )
        end

        # An explicit false is a setting, not an absent one. Filtering on
        # truthiness rather than on undef would silently drop it.
        it 'keeps a setting whose value is false' do
          expect(written_config(catalogue)['agent']['prune_environments']).to be(false)
        end
      end

      # An estate whose certificates predate codavox has no pp_role anywhere, so
      # naming compilers has to work with no roles configured at all.
      context 'with certnames and no roles' do
        let(:params) do
          {
            publish_allow_certnames: ['legacy01.example.com'],
          }
        end

        it { is_expected.to compile.with_all_deps }

        it 'writes the certname allowlist and no role key' do
          publish = written_config(catalogue)['publish']
          expect(publish).to eq('allow_certnames' => ['legacy01.example.com'])
        end
      end

      context 'with an invalid certificate_revocation' do
        let(:params) { { publish_certificate_revocation: 'chian' } }

        # A typo must fail at compile time. codavox treats an unrecognised value
        # as an error too, but catching it here names the parameter.
        it { is_expected.to compile.and_raise_error(%r{publish_certificate_revocation}) }
      end
    end
  end
end
