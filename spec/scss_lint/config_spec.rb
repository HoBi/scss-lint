require 'spec_helper'
require 'fileutils'

describe SCSSLint::Config do
  class SCSSLint::Linter::FakeConfigLinter < SCSSLint::Linter; end

  module SCSSLint::Linter::SomeNamespace
    class FakeLinter1 < SCSSLint::Linter; end
    class FakeLinter2 < SCSSLint::Linter; end
  end

  let(:default_file) { File.open(described_class::DEFAULT_FILE).read }

  # This complex stubbing bypasses the built-in caching of the methods, and at
  # the same time gives us full control over the "default" configuration.
  before do
    described_class
      .stub(:load_file_contents)
      .with(described_class::DEFAULT_FILE)
      .and_return(default_file)

    described_class
      .stub(:default_options_hash)
      .and_return(described_class.send(:load_options_hash_from_file, described_class::DEFAULT_FILE))

    described_class
      .stub(:default)
      .and_return(described_class.load(described_class::DEFAULT_FILE, merge_with_default: false))
  end

  describe '.default' do
    subject { described_class.default }

    it 'has a configuration defined for all registered linters' do
      SCSSLint::LinterRegistry.linters.map(&:new).each do |linter|
        subject.linter_options(linter).should_not be_nil
      end
    end
  end

  describe '.load' do
    let(:config_dir) { '/path/to' }
    let(:file_name) { "/#{config_dir}/config.yml" }

    let(:default_file) { <<-FILE }
    linters:
      FakeConfigLinter:
        enabled: true
      OtherFakeConfigLinter:
        enabled: false
    FILE

    subject { described_class.load(file_name) }

    before do
      described_class.stub(:load_file_contents)
                     .with(file_name)
                     .and_return(config_file)
    end

    context 'with an empty config file' do
      let(:config_file) { '' }

      it 'returns the default configuration' do
        subject.options.should == described_class.default.options
      end
    end

    context 'with a config file containing only comments' do
      let(:config_file) { '# This is a comment' }

      it 'returns the default configuration' do
        subject.options.should == described_class.default.options
      end
    end

    context 'with a file configuring an unknown linter' do
      let(:config_file) { 'linters: { MadeUpLinterName: { enabled: true } }' }

      it 'stores a warning for the unknown linter' do
        subject.warnings
               .any? { |warning| warning.include?('MadeUpLinterName') }
               .should be true
      end
    end

    context 'with a config file setting the same configuration as the default' do
      let(:config_file) { default_file }

      it 'returns a configuration equivalent to the default' do
        subject.options.should == described_class.default.options
      end
    end

    context 'with a config file setting the same subset of settings as the default' do
      let(:config_file) { <<-FILE }
      linters:
        FakeConfigLinter:
          enabled: true
      FILE

      it 'returns a configuration equivalent to the default' do
        subject.options.should == described_class.default.options
      end
    end

    context 'when a wildcard is used for a namespaced linter' do
      let(:default_file) { <<-FILE }
      linters:
        SomeNamespace::*:
          enabled: false
      FILE

      let(:config_file) { <<-FILE }
      linters:
        SomeNamespace::*:
          enabled: true
      FILE

      before do
        SCSSLint::LinterRegistry.stub(:linters)
          .and_return([SCSSLint::Linter::SomeNamespace::FakeLinter1,
                       SCSSLint::Linter::SomeNamespace::FakeLinter2])
      end

      it 'returns the same options for all linters under that namespace' do
        subject.linter_options(SCSSLint::Linter::SomeNamespace::FakeLinter1)
          .should eq('enabled' => true)
        subject.linter_options(SCSSLint::Linter::SomeNamespace::FakeLinter2)
          .should eq('enabled' => true)
      end
    end
  end

  describe '#linter_options' do
    let(:config) { described_class.new(options) }

    let(:linter_options) do
      {
        'enabled' => true,
        'some_option' => 'some_value',
      }
    end

    let(:options) do
      {
        'linters' => {
          'FakeConfigLinter' => linter_options
        }
      }
    end

    it 'returns the options for the specified linter' do
      config.linter_options(SCSSLint::Linter::FakeConfigLinter.new)
        .should == linter_options
    end
  end

  describe '#excluded_file?' do
    include_context 'isolated environment'

    let(:config_dir) { 'path/to' }
    let(:file_name) { "#{config_dir}/config.yml" }
    let(:config) { described_class.load(file_name) }

    before do
      described_class.stub(:load_file_contents)
                     .with(file_name)
                     .and_return(config_file)
    end

    context 'when no exclusion is specified' do
      let(:config_file) { 'linters: {}' }

      it 'does not exclude any files' do
        config.excluded_file?('anything/you/want.scss').should be false
      end
    end

    context 'when an exclusion is specified' do
      let(:config_file) { "exclude: 'foo/bar/baz/**'" }

      it 'does not exclude anything not matching the glob' do
        config.excluded_file?("#{config_dir}/foo/bar/something.scss").should be false
        config.excluded_file?("#{config_dir}/other/something.scss").should be false
      end

      it 'excludes anything matching the glob' do
        config.excluded_file?("#{config_dir}/foo/bar/baz/excluded.scss").should be true
        config.excluded_file?("#{config_dir}/foo/bar/baz/dir/excluded.scss").should be true
      end
    end
  end

  describe '#excluded_file_for_linter?' do
    include_context 'isolated environment'

    let(:config_dir) { 'path/to' }
    let(:file_name) { "#{config_dir}/config.yml" }
    let(:config) { described_class.load(file_name) }

    before do
      described_class.stub(:load_file_contents)
                     .with(file_name)
                     .and_return(config_file)
    end

    context 'when no exclusion is specified in linter' do
      let(:config_file) { <<-FILE }
      linters:
        FakeConfigLinter:
          enabled: true
      FILE

      it 'does not exclude any files' do
        config.excluded_file_for_linter?(
          "#{config_dir}/anything/you/want.scss",
          SCSSLint::Linter::FakeConfigLinter.new
        ).should == false
      end
    end

    context 'when an exclusion is specified in linter' do
      let(:config_file) { <<-FILE }
      linters:
        FakeConfigLinter:
          enabled: true
          exclude:
            - 'anything/you/want.scss'
      FILE

      it 'excludes file for the linter' do
        config.excluded_file_for_linter?(
          "#{config_dir}/anything/you/want.scss",
          SCSSLint::Linter::FakeConfigLinter.new
        ).should == true
      end
    end
  end
end
