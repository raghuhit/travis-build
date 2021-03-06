require 'spec_helper'

describe Travis::Build::Script, :sexp do
  let(:config)  { PAYLOADS[:worker_config] }
  let(:payload) { payload_for(:push, :ruby, config: { addons: {}, cache: 'bundler'}).merge(config) }
  let(:script)  { Travis::Build.script(payload) }
  let(:code)    { script.compile }
  subject       { script.sexp }

  it 'raises an exception if the generated code is tainted (leaking secure env vars)' do
    payload[:config][:env] = ['SECURE FOO=foo']
    Travis::Build::Env::Var.any_instance.stubs(:secure?).returns(false)
    expect { code }.to raise_error(Travis::Shell::Generator::TaintedOutput)
  end

  it 'uses $HOME/build as a working directory' do
    expect(code).to match %r(cd +\$HOME/build)
  end

  it 'applies resolv.conf fix' do
    should include_sexp [:raw, %r(tee /etc/resolv.conf)]
  end

  it 'applies /etc/hosts fix' do
    should include_sexp [:raw, %r(sed .* /etc/hosts)]
  end

  it 'applies PS4 fix' do
    should include_sexp [:export, ['PS4', '+']]
  end

  it 'disables sudo' do
    should include_sexp [:cmd, %r(rm -f /etc/sudoers.d/travis)]
  end

  it 'runs casher fetch' do
    should include_sexp [:cmd, /casher fetch/, :*]
  end

  it 'runs casher push' do
    should include_sexp [:cmd, /casher push/, :*]
  end

  describe 'does not exlode' do
    it 'on script being true' do
      payload[:config][:script] = true
      expect { subject }.to_not raise_error
    end

    it 'if s3_options are tainted' do
      payload['cache_options']['s3']['access_key_id'].taint
      expect { code }.to_not raise_error
    end
  end

  context 'when install phase is `"skip"`' do
    it 'execute `travis_run_install` function, and set the test result' do
      payload[:config][:install] = 'skip'
      should include_sexp [:raw, 'travis_run_install']
      should_not include_sexp [:raw, 'travis_result 0'] # these functions are hard to test, extract an bash ast type :function?
    end
  end

  context 'when script phase is `"skip"`' do
    it 'execute `travis_run_script` function, and set the test result' do
      payload[:config][:script] = 'skip'
      should include_sexp [:raw, 'travis_run_install']
      should include_sexp [:raw, 'travis_result 0'] # these functions are hard to test, extract an bash ast type :function?
    end
  end

  context 'when script phase is `["skip"]`' do
    it 'execute `travis_run_script` function, and set the test result' do
      payload[:config][:script] = ['skip']
      should include_sexp [:raw, 'travis_run_install']
      should include_sexp [:raw, 'travis_result 0'] # these functions are hard to test, extract an bash ast type :function?
    end
  end

  context 'when before_install phase is `["skip"]`' do
    it 'executes `travis_run_before_install` function' do
      payload[:config][:before_install] = ['skip']

      should include_sexp [:raw, 'travis_run_install']
    end
  end

  context 'when running a debug build' do
    let(:payload) { payload_for(:push_debug, :ruby, config: { cache: ['apt', 'bundler'] }).merge(config) }
    it_behaves_like 'a debug script'
  end

  context 'apt-get update' do
    context 'with APT_GET_UPDATE_OPT_IN not enabled' do
      context 'with running on osx' do
        before { payload[:config][:os] = 'osx' }
        before { payload[:config].delete(:apt) }
        after { payload[:config][:os] = 'linux' }
        it { expect(code).to_not include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get by default has been disabled' }
      end

      context 'with config[:apt][:update] not given' do
        before { payload[:config].delete(:apt) }
        before { payload[:config][:os] = 'linux' }
        it { expect(code).to include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:apt][:update] not given and apt-get update used in before_install' do
        before { payload[:config][:install] = ['apt-get -s install foo'] }
        it { expect(code).to_not include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:apt][:update] being true' do
        before { payload[:config][:apt] = { update: true } }
        it { expect(code).to include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:apt][:update] being false' do
        before { payload[:config][:apt] = { update: false } }
        it { expect(code).to_not include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:addons][:apt][:update] being true' do
        before { payload[:config][:addons][:apt] = { update: true } }
        it { expect(code).to include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:addons][:apt][:update] being false' do
        before { payload[:config][:addons][:apt] = { update: false } }
        it { expect(code).to_not include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get update by default has been disabled' }
      end
    end

    context 'with APT_GET_UPDATE_OPT_IN enabled' do
      before { ENV['APT_GET_UPDATE_OPT_IN'] = 'true' }
      after { ENV.delete('APT_GET_UPDATE_OPT_IN') }
      
      context 'with running on osx' do
        before { payload[:config][:os] = 'osx' }
        after { payload[:config][:os] = 'linux' }
        it { expect(code).to_not include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get by default has been disabled' }
      end

      context 'with config[:apt][:update] not given' do
        before { payload[:config].delete(:apt) }
        it { expect(code).to_not include 'sudo apt-get update' }
        it { expect(code).to include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:apt][:update] not given and apt-get update used in before_install' do
        before { payload[:config][:install] = ['apt-get -s install foo'] }
        it { code }
        it { expect(code).to include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:apt][:update] being true' do
        before { payload[:config][:apt] = { update: true } }
        it { expect(code).to include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:apt][:update] being false' do
        before { payload[:config][:apt] = { update: false } }
        it { expect(code).to_not include 'sudo apt-get update' }
        it { expect(code).to include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:addons][:apt][:update] being true' do
        before { payload[:config][:addons][:apt] = { update: true } }
        it { expect(code).to include 'sudo apt-get update' }
        it { expect(code).to_not include 'Running apt-get update by default has been disabled' }
      end

      context 'with config[:addons][:apt][:update] being false' do
        before { payload[:config][:addons][:apt] = { update: false } }
        it { expect(code).to_not include 'sudo apt-get update' }
        it { expect(code).to include 'Running apt-get update by default has been disabled' }
      end
    end
  end
end
