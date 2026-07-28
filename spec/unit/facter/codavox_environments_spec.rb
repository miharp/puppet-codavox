# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

describe 'codavox_environments fact' do
  subject(:fact) { Facter.fact(:codavox_environments) }

  let(:config) { '/etc/codavox/config.yaml' }
  let(:tmpdir) { Dir.mktmpdir }
  let(:envdir) { File.join(tmpdir, 'environments') }

  before do
    FileUtils.mkdir_p(envdir)
    Facter.clear
    # The fact confines to Linux, and the suite runs on whatever the developer
    # has.
    allow(Facter.fact(:kernel)).to receive(:value).and_return('Linux')

    # Only the two hardcoded paths are stubbed. Everything the fact actually
    # parses is a real symlink on disk, because the parsing is the part worth
    # testing.
    allow(File).to receive(:readable?).and_call_original
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:readable?).with(config).and_return(true)
    allow(File).to receive(:read).with(config).and_return("environmentpath: #{envdir}\n")
  end

  after { FileUtils.remove_entry(tmpdir) }

  # Mirrors what the agent leaves behind: a version directory, and an
  # environment symlink pointing at it.
  def deploy(env, code_id)
    version = File.join(envdir, "#{env}_#{code_id}")
    FileUtils.mkdir_p(version)
    FileUtils.ln_s(version, File.join(envdir, env))
  end

  it 'reports nothing when the agent has not converged' do
    # Not nil and not an error: a node that has just installed codavox has
    # genuinely converged on nothing, and a manifest needs to branch on that.
    expect(fact.value).to eq({})
  end

  it 'reports the code_id the environment symlink points at' do
    deploy('production', 'a1b2c3d4e5f6')
    expect(fact.value).to eq('production' => 'a1b2c3d4e5f6')
  end

  it 'reports every converged environment' do
    deploy('production', 'aaa111')
    deploy('testing', 'bbb222')
    expect(fact.value).to eq('production' => 'aaa111', 'testing' => 'bbb222')
  end

  it 'splits on the last underscore, so environment names may contain one' do
    # The whole reason for rpartition. Splitting on the first underscore would
    # report `env_def456` as the code_id of `my`, and nothing would ever match.
    deploy('my_env', 'def456')
    expect(fact.value).to eq('my_env' => 'def456')
  end

  it 'ignores directories that are not environment symlinks' do
    deploy('production', 'aaa111')
    expect(fact.value).to eq('production' => 'aaa111')
  end

  it 'ignores a plain directory placed in environmentpath' do
    FileUtils.mkdir_p(File.join(envdir, 'notalink'))
    expect(fact.value).to eq({})
  end

  it 'ignores a symlink whose target carries no code_id' do
    # Reporting `production => bare` here would be the exact failure codavox
    # exists to prevent: a version that describes nothing, reported as though
    # the node had converged.
    target = File.join(envdir, 'bare')
    FileUtils.mkdir_p(target)
    FileUtils.ln_s(target, File.join(envdir, 'production'))
    expect(fact.value).to eq({})
  end

  it 'ignores a symlink pointing at another environment version directory' do
    # Corrupt state rather than something the agent produces. The code_id is
    # real, but it is not production's, and a manifest branching on this would
    # wire the server against an environment that is not there.
    target = File.join(envdir, 'testing_bbb222')
    FileUtils.mkdir_p(target)
    FileUtils.ln_s(target, File.join(envdir, 'production'))
    expect(fact.value).to eq({})
  end

  context 'when environmentpath is not configured' do
    before do
      allow(File).to receive(:read).with(config).and_return("basedir: /etc/puppetlabs/code/environments\n")
    end

    # Falls back to the packaged default, which is not the tmpdir, so nothing
    # is found. The point is that it looks somewhere plausible rather than
    # raising.
    it { expect(fact.value).to eq({}) }
  end

  context 'when the config file is unreadable' do
    before do
      allow(File).to receive(:readable?).with(config).and_return(false)
    end

    it { expect(fact.value).to eq({}) }
  end

  context 'when the config file is malformed' do
    before do
      allow(File).to receive(:read).with(config).and_return("environmentpath: [unclosed\n")
    end

    # codavox reports a broken config loudly when it starts. A fact that raised
    # here would instead fail every catalog compile on the node, over a file it
    # only consults for a path.
    it { expect { fact.value }.not_to raise_error }
    it { expect(fact.value).to eq({}) }
  end

  context 'on a platform that is not Linux' do
    before do
      allow(Facter.fact(:kernel)).to receive(:value).and_return('Darwin')
    end

    it { expect(fact.value).to be_nil }
  end
end
