require 'spec_helper'
require 'td/command/common'
require 'td/command/list'
require 'td/command/workflow'

def java_available?
  begin
    output, status = Open3.capture2e('java', '-version')
  rescue
    return false
  end
  if not status.success?
    return false
  end
  if output !~ /(openjdk|java) version "1/
    return false
  end
  return true
end

STDERR.puts
STDERR.puts("RUBY_PLATFORM: #{RUBY_PLATFORM}")
STDERR.puts("on_64bit_os?: #{TreasureData::Helpers.on_64bit_os?}")
STDERR.puts("java_available?: #{java_available?}")
STDERR.puts

module TreasureData::Command

  describe 'workflow command' do

    let(:command) {
      Class.new { include TreasureData::Command }.new
    }
    let(:stdout_io) { StringIO.new }
    let(:stderr_io) { StringIO.new }
    let(:home_env) { TreasureData::Helpers.on_windows? ? 'USERPROFILE' : 'HOME' }
    let(:java_exe) { TreasureData::Helpers.on_windows? ? 'java.exe' : 'java' }

    around do |example|

      stdout = $stdout.dup
      stderr = $stderr.dup

      begin
        $stdout = stdout_io
        $stderr = stderr_io

        Dir.mktmpdir { |home|
          with_env(home_env, home) {
            example.run
          }
        }
      ensure
        $stdout = stdout
        $stderr = stderr
      end
    end

    def with_env(name, var)
      backup, ENV[name] = ENV[name], var
      begin
        yield
      ensure
        ENV[name] = backup
      end
    end

    let(:tmpdir) {
      Dir.mktmpdir
    }

    let(:project_dir) {
      File.join(tmpdir,'foobar')
    }

    let(:td_conf) {
      File.join(tmpdir,'td.conf')
    }

    after(:each) {
      FileUtils.rm_rf tmpdir
    }

    describe '#workflow' do
      let(:option) {
        List::CommandParser.new("workflow", [], [], nil, [], true)
      }

      let(:init_option) {
        List::CommandParser.new("workflow", [], [], nil, ['init', project_dir], true)
      }

      let(:reset_option) {
        List::CommandParser.new("workflow:reset", [], [], nil, [], true)
      }

      let (:apikey) {
        '4711/badf00d'
      }

      before(:each) {
        allow(TreasureData::Config).to receive(:apikey) { apikey }
        allow(TreasureData::Config).to receive(:path) { td_conf }
        File.write(td_conf, [
            '[account]',
            '  user = test@example.com',
            "  apikey = #{apikey}",
        ].join($/) + $/)
      }

      it 'complains about 32 bit platform if no usable java on path' do
        allow(TreasureData::Helpers).to receive(:on_64bit_os?) {false}
        with_env('PATH', '') do
          expect{command.workflow(option, capture_output=true)}.to raise_error(WorkflowError) { |error|
            expect(error.message).to include(<<EOF
A suitable installed version of Java could not be found and and Java cannot be
automatically installed for this OS.

Please install at least Java 8u71.
EOF
)
          }
        end
      end

      it 'uses system java by default on 32 bit platforms' do
        allow(TreasureData::Helpers).to receive(:on_64bit_os?) {false}
        expect(java_available?).to be(true)

        allow(TreasureData::Updater).to receive(:stream_fetch).and_call_original
        allow($stdin).to receive(:gets) { 'Y' }
        status = command.workflow(option, capture_output=true)
        expect(status).to be 0
        expect(stdout_io.string).to_not include 'Downloading Java'
        expect(stdout_io.string).to include 'Downloading workflow module'
        expect(File).to exist(File.join(ENV[home_env], '.td', 'digdag', 'digdag'))
        expect(TreasureData::Updater).to_not have_received(:stream_fetch).with(
            %r{/java/}, instance_of(File))
        expect(TreasureData::Updater).to have_received(:stream_fetch).with(
            'http://toolbelt.treasure-data.com/digdag?user=test%40example.com', instance_of(File))
      end

      it 'installs java and digdag' do
        skip 'Requires 64 bit OS' unless TreasureData::Helpers::on_64bit_os?

        allow(TreasureData::Updater).to receive(:stream_fetch).and_call_original
        allow($stdin).to receive(:gets) { 'Y' }
        status = command.workflow(option, capture_output=true)
        expect(status).to be 0
        expect(stdout_io.string).to include 'Downloading Java'
        expect(File).to exist(File.join(ENV[home_env], '.td', 'digdag', 'jre', 'bin', java_exe))
        expect(TreasureData::Updater).to have_received(:stream_fetch).with(
            %r{/java/}, instance_of(File))
        expect(stdout_io.string).to include 'Downloading workflow module'
        expect(File).to exist(File.join(ENV[home_env], '.td', 'digdag', 'digdag'))
        expect(TreasureData::Updater).to have_received(:stream_fetch).with(
            'http://toolbelt.treasure-data.com/digdag?user=test%40example.com', instance_of(File))

        # Check that java and digdag is not re-installed
        stdout_io.truncate(0)
        stderr_io.truncate(0)
        status = command.workflow(option, capture_output=true)
        expect(status).to be 0
        expect(stdout_io.string).to_not include 'Downloading Java'
        expect(stdout_io.string).to_not include 'Downloading workflow module'

        # Check that it can run a digdag command
        stdout_io.truncate(0)
        stderr_io.truncate(0)
        status = command.workflow(init_option, capture_output=true)
        expect(status).to be 0
        expect(stdout_io.string).to include('Creating')
      end

      it 'uses specified java and installs digdag' do
        with_env('TD_WF_JAVA', 'echo') {
          allow(TreasureData::Updater).to receive(:stream_fetch).and_call_original
          allow($stdin).to receive(:gets) { 'Y' }
          status = command.workflow(option, capture_output=true)
          expect(status).to be 0
          expect(stdout_io.string).to_not include 'Downloading Java'
          expect(stdout_io.string).to include 'Downloading workflow module'
          expect(File).to exist(File.join(ENV[home_env], '.td', 'digdag', 'digdag'))
          expect(TreasureData::Updater).to_not have_received(:stream_fetch).with(
              %r{/java/}, instance_of(File))
          expect(TreasureData::Updater).to have_received(:stream_fetch).with(
              'http://toolbelt.treasure-data.com/digdag?user=test%40example.com', instance_of(File))

          # Check that digdag is not re-installed
          stdout_io.truncate(0)
          stderr_io.truncate(0)
          status = command.workflow(option, capture_output=true)
          expect(status).to be 0
          expect(stdout_io.string).to_not include 'Downloading Java'
          expect(stdout_io.string).to_not include 'Downloading workflow module'
        }
      end

      it 'reinstalls cleanly after reset' do
        skip 'Requires 64 bit OS or system java' unless (TreasureData::Helpers::on_64bit_os? or java_available?)

        # First install
        allow($stdin).to receive(:gets) { 'Y' }
        status = command.workflow(option, capture_output=true)
        expect(status).to be 0
        expect(stderr_io.string).to include 'Digdag v'
        expect(File).to exist(File.join(ENV[home_env], '.td', 'digdag'))

        # Reset
        stdout_io.truncate(0)
        stderr_io.truncate(0)
        status = command.workflow_reset(reset_option)
        expect(status).to be 0
        expect(File).to_not exist(File.join(ENV[home_env], '.td', 'digdag'))
        expect(File).to exist(File.join(ENV[home_env], '.td'))
        expect(stdout_io.string).to include 'Removing workflow module...'
        expect(stdout_io.string).to include 'Done'

        # Reinstall
        allow($stdin).to receive(:gets) { 'Y' }
        stdout_io.truncate(0)
        stderr_io.truncate(0)
        status = command.workflow(option, capture_output=true)
        expect(status).to be 0
        expect(stderr_io.string).to include 'Digdag v'
        expect(File).to exist(File.join(ENV[home_env], '.td', 'digdag'))
      end

      it 'uses -k apikey' do
        with_env('TD_WF_JAVA', 'echo') {
          allow(TreasureData::Config).to receive(:cl_apikey) { true }
          stdout_io.truncate(0)
          stderr_io.truncate(0)
          status = command.workflow(init_option, capture_output=true, check_prereqs=false)
          expect(status).to be 0
          expect(stdout_io.string).to match(/--config/)
          expect(stdout_io.string).to_not include('io.digdag.standards.td.client-configurator.enabled=true')
        }
      end
    end
  end
end
