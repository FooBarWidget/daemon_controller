# frozen_string_literal: true

require_relative "test_helper"
require "daemon_controller"
require "benchmark"
require "socket"
require "tmpdir"
require "shellwords"

describe DaemonController, "#start" do
  include TestHelper

  after :each do
    @controller.stop if @controller
  end

  it "works" do
    new_controller
    @controller.start
    expect(ping_echo_server).to be(true)
  end

  it "raises AlreadyStarted if the daemon is already running" do
    new_controller
    begin
      expect(@controller).to receive(:daemon_is_running?).and_return(true)
      expect { @controller.start }.to raise_error(DaemonController::AlreadyStarted)
    ensure
      @controller = nil # Don't invoke @controller.stop in after hook
    end
  end

  it "deletes existing PID file before starting the daemon" do
    write_file("spec/echo_server.pid", "1234")
    new_controller
    expect(@controller).to receive(:daemon_is_running?).and_return(false)
    expect(@controller).to receive(:spawn_daemon)
    expect(@controller).to receive(:pid_file_available?).and_return(true)
    expect(@controller).to receive(:run_ping_command).at_least(:once).and_return(true)
    @controller.start
    expect(File.exist?("spec/echo_server.pid")).to be false
  ensure
    @controller = nil # Don't invoke @controller.stop in after hook
  end

  it "blocks until the daemon has written to its PID file" do
    thread = WaitingThread.new do
      sleep 0.15
      write_file("spec/echo_server.pid", "1234")
    end
    new_controller
    expect(@controller).to receive(:daemon_is_running?) { false }
    expect(@controller).to receive(:spawn_daemon) { thread.go! }
    expect(@controller).to receive(:run_ping_command).at_least(:once).and_return(true)
    begin
      result = Benchmark.measure do
        @controller.start
      end
      expect(result.real).to be_between(0.15, 0.30)
    ensure
      thread.join
    end
  ensure
    @controller = nil # Don't invoke @controller.stop in after hook
  end

  it "blocks until the daemon can be pinged" do
    ping_ok = false
    running = false
    thread = WaitingThread.new do
      sleep 0.15
      ping_ok = true
    end
    new_controller
    expect(@controller).to receive(:daemon_is_running?).at_least(:once) { running }
    expect(@controller).to receive(:spawn_daemon) {
      thread.go!
      running = true
    }
    expect(@controller).to receive(:pid_file_available?).and_return(true)
    expect(@controller).to receive(:run_ping_command).at_least(:once) { ping_ok }
    begin
      result = Benchmark.measure do
        @controller.start
      end
      expect(result.real).to be_between(0.15, 0.30)
    ensure
      thread.join
    end
  ensure
    @controller = nil # Don't invoke @controller.stop in after hook
  end

  it "works when the log file is not a regular file" do
    new_controller(log_file: "/dev/stderr")
    @controller.start
    expect(ping_echo_server).to be(true)
  end

  context "if the daemon doesn't start in time" do
    let(:start_timeout) { exec_is_slow? ? 4 : 0.5 }
    let(:min_start_timeout) { 0.5 }
    let(:max_start_timeout) { exec_is_slow? ? 6 : 1 }

    it "raises StartTimeout" do
      new_controller(start_command: "sleep 2", start_timeout: start_timeout)
      start_time = Time.now
      end_time = nil
      expect(@controller).to receive(:start_timed_out) { end_time = Time.now }
      expect { @controller.start }.to raise_error(DaemonController::StartTimeout)
      expect(end_time - start_time).to be_between(min_start_timeout, max_start_timeout)
    end

    it "reports logs written to stderr if the timeout happened before forking" do
      new_controller(start_command: "echo hello world; sleep 10", start_timeout: start_timeout)
      expect(@controller).to receive(:daemonization_timed_out)
      begin
        @controller.start
        fail
      rescue DaemonController::StartTimeout => e
        expect(e.message).to include("hello world")
      end
    end

    it "reports logs written to the log file if the timeout happened before forking" do
      new_controller(log_message2: "hello world",
        wait2: 10,
        start_timeout: start_timeout,
        no_daemonize: true)
      expect(@controller).to receive(:daemonization_timed_out)
      begin
        @controller.start
        fail
      rescue DaemonController::StartTimeout => e
        expect(e.message).to include("hello world")
      end
    end

    it "reports logs if the timeout happened after forking" do
      new_controller(log_message2: "hello world",
        wait2: 10,
        start_timeout: start_timeout)
      expect(@controller).not_to receive(:daemonization_timed_out)
      begin
        @controller.start
        fail
      rescue DaemonController::StartTimeout => e
        expect(e.message).to include("hello world")
      end
    end

    specify "if there are no logs, then the error says so" do
      new_controller(start_command: "sleep 10", start_timeout: start_timeout)
      expect(@controller).to receive(:daemonization_timed_out)
      begin
        @controller.start
        fail
      rescue DaemonController::StartTimeout => e
        expect(e.message).to eq("(logs empty; timed out)")
      end
    end

    specify "if logs cannot be captured, then the error says so" do
      new_controller(start_command: "sleep 10", start_timeout: start_timeout, log_file: "/dev/stderr")
      expect(@controller).to receive(:daemonization_timed_out)
      begin
        @controller.start
        fail
      rescue DaemonController::StartTimeout => e
        expect(e.message).to eq("(logs not available; timed out)")
      end
    end
  end

  it "kills the daemon forcefully if the daemon has forked but doesn't " \
    "become pingable in time, and there's a PID file" do
    new_controller(wait2: 3, start_timeout: 1)
    pid = nil
    expect(@controller).to receive(:start_timed_out) {
      @controller.send(:wait_until) do
        @controller.send(:pid_file_available?)
      end
      pid = @controller.send(:read_pid_file)
    }
    begin
      block = lambda { @controller.start }
      expect(&block).to raise_error(DaemonController::StartTimeout)
      eventually(1) do
        !process_is_alive?(pid)
      end

      # The daemon should not be able to clean up its PID file since
      # it's killed with SIGKILL.
      expect(File.exist?("spec/echo_server.pid")).to be true
    ensure
      begin
        File.unlink("spec/echo_server.pid")
      rescue
        nil
      end
    end
  end

  it "kills the daemon if it doesn't start in time and hasn't forked yet" do
    new_controller(start_command: "./spec/unresponsive_daemon.rb",
      start_timeout: 0.2)
    pid = nil
    expect(@controller).to receive(:daemonization_timed_out) {
      @controller.send(:wait_until) do
        @controller.send(:pid_file_available?)
      end
      pid = @controller.send(:read_pid_file)
    }
    block = lambda { @controller.start }
    expect(&block).to raise_error(DaemonController::StartTimeout, /logs empty/)
    eventually(1) do
      !process_is_alive?(pid)
    end
  ensure
    begin
      File.unlink("spec/echo_server.pid")
    rescue
      nil
    end
  end

  it "raises an error if the daemon exits with an error before forking" do
    new_controller(start_command: "false")
    expect { @controller.start }.to raise_error(DaemonController::StartError)
  end

  it "raises an error if the daemon exits with an error after forking" do
    new_controller(crash_before_bind: true)
    expect { @controller.start }.to raise_error(DaemonController::StartError)
  end

  specify "if the daemon exits after forking without writing a PID file, then this is detected through log file inactivity" do
    new_controller(log_message1: "hello",
      log_message2: "world",
      no_write_pid_file: true,
      log_file_activity_timeout: 0.5)
    begin
      @controller.start
      fail
    rescue DaemonController::StartTimeout => e
      expect(e.message).to include("hello")
      expect(e.message).to include("world")
      expect(e.message).to include("(timed out)")
    ensure
      # Kill echo_server without PID file
      kill_and_wait_echo_server
    end
  end

  def find_echo_server_pid
    process_line = `ps aux`.lines.grep(/echo_server\.rb/).first
    process_line.split[1].to_i if process_line
  end

  def kill_and_wait_echo_server
    pid = find_echo_server_pid
    if pid
      Process.kill("SIGTERM", pid)
      Timeout.timeout(5) do
        while find_echo_server_pid
          sleep(0.1)
        end
      end
    end
  end

  specify "the daemon's logs before forking is made available in the exception" do
    new_controller(start_command: "(echo hello world; false)")
    begin
      @controller.start
    rescue DaemonController::StartError => e
      expect(e.message).to eq("hello world\n(exited with status 1)")
    end
  end

  specify "the daemon's logs after forking is made available in the exception" do
    new_controller(crash_before_bind: true)
    begin
      @controller.start
      fail
    rescue DaemonController::StartError => e
      expect(e.message).to include("crashing, as instructed")
    end
  end

  specify "the daemon's exit signal is made available in the exception if the log file is a regular file" do
    new_controller(crash_before_bind: true, crash_signal: "SIGXCPU", no_daemonize: true)
    begin
      @controller.start
      fail
    rescue DaemonController::StartError => e
      expect(e.message).to include("crashing, as instructed")
      expect(e.message).to include("SIGXCPU")
    end
  end

  specify "the daemon's exit signal is made available in the exception if the log file is not a regular file" do
    new_controller(crash_before_bind: true,
      crash_signal: "SIGXCPU",
      no_daemonize: true,
      log_file: "/dev/stderr")
    begin
      @controller.start
      fail
    rescue DaemonController::StartError => e
      expect(e.message).to include("logs not available")
      expect(e.message).to include("SIGXCPU")
    end
  end

  specify "the daemon's logs are not available if the log file is not a regular file" do
    new_controller(crash_before_bind: true, log_file: "/dev/stderr")
    begin
      @controller.start
      fail
    rescue DaemonController::StartError => e
      expect(e.message).to eq("(logs not available)")
    end
  end

  specify "if the logs are available but empty, then the error exception says so" do
    new_controller(start_command: "exit 1")
    begin
      @controller.start
      fail
    rescue DaemonController::StartError => e
      expect(e.message).to eq("(logs empty; exited with status 1)")
    end
  end

  specify "the start command may be a Proc" do
    called = true
    new_controller(start_command: lambda {
      called = true
      @start_command
    })
    @controller.start
    expect(called).to be true
  end

  specify "if the start command is a Proc then it is called after before_start" do
    log = []
    new_controller(
      start_command: lambda {
        log << "start_command"
        @start_command
      },
      before_start: lambda { log << "before_start" }
    )
    @controller.start
    expect(log).to eq(["before_start", "start_command"])
  end

  it "keeps the file descriptors in 'keep_ios' open" do
    a, b = IO.pipe
    begin
      new_controller(keep_ios: [b])
      @controller.start
      b.close
      expect(select([a], nil, nil, 0)).to be_nil
    ensure
      a.close if !a.closed?
      b.close if !b.closed?
    end
  end

  it "performs the daemonization on behalf of the daemon if 'daemonize_for_me' is set" do
    new_controller(no_daemonize: true, daemonize_for_me: true)
    @controller.start
    expect(ping_echo_server).to be true
  end

  it "receives environment variables" do
    new_controller(env: {"ENV_FILE" => "spec/env_file.tmp"})
    File.unlink("spec/env_file.tmp") if File.exist?("spec/env_file.tmp")
    @controller.start
    expect(File.exist?("spec/env_file.tmp")).to be true
  end
end

describe DaemonController, "#stop" do
  include TestHelper

  before :each do
    new_controller
  end

  after :each do
    @controller.stop if @controller
  end

  it "raises no exception if the daemon is not running" do
    @controller.stop
  end

  it "waits until the daemon is no longer running" do
    new_controller(stop_time: 0.3)
    @controller.start
    result = Benchmark.measure do
      @controller.stop
    end
    expect(@controller).not_to be_running
    expect(result.real).to be_between(0.3, 0.6)
  end

  it "raises StopTimeout if the daemon does not stop in time" do
    new_controller(stop_time: 0.3, stop_timeout: 0.1)
    @controller.start
    begin
      expect { @controller.stop }.to raise_error(DaemonController::StopTimeout)
    ensure
      new_controller.stop
    end
  end

  describe "if stop command was given" do
    it "raises StopError if the stop command exits with an error" do
      new_controller(stop_command: "(echo hello world; false)")
      begin
        begin
          @controller.stop
          fail
        rescue DaemonController::StopError => e
          expect(e.message).to eq("hello world\n(exited with status 1)")
        end
      ensure
        new_controller.stop
      end
    end

    it "makes the stop command's error message available in the exception" do
    end

    it "calls the stop command if the PID file is invalid and :dont_stop_if_pid_file_invalid is not set" do
      Dir.mktmpdir do |tmpdir|
        File.open("spec/echo_server.pid", "w").close
        new_controller(stop_command: "touch #{Shellwords.escape tmpdir}/stopped")
        @controller.stop
        expect(File.exist?("#{tmpdir}/stopped")).to be_truthy
      end
    ensure
      @controller = nil
    end

    it "does not call the stop command if the PID file is invalid and :dont_stop_if_pid_file_invalid is set" do
      Dir.mktmpdir do |tmpdir|
        File.open("spec/echo_server.pid", "w").close
        new_controller(stop_command: "touch #{Shellwords.escape tmpdir}/stopped",
          dont_stop_if_pid_file_invalid: true)
        @controller.stop
        expect(File.exist?("#{tmpdir}/stopped")).to be_falsey
      end
    end
  end
end

describe DaemonController, "#restart" do
  include TestHelper

  before :each do
    new_controller
  end

  it "raises no exception if the daemon is not running" do
    @controller.restart
  end

  describe "with no restart command" do
    it "restart the daemon using stop and start" do
      expect(@controller).to receive(:stop)
      expect(@controller).to receive(:start)
      @controller.restart
    end
  end

  describe "with a restart_command" do
    it "restarts the daemon using the restart_command" do
      stop_cmd = "echo 'hello world'"
      new_controller restart_command: stop_cmd

      expect(@controller).to receive(:run_command).with(stop_cmd)
      @controller.restart
    end
  end
end

describe DaemonController, "#connect" do
  include TestHelper

  before :each do
    new_controller
  end

  it "starts the daemon if it isn't already running" do
    socket = @controller.connect do
      TCPSocket.new("localhost", 3230)
    end
    socket.close
    @controller.stop
  end

  it "connects to the existing daemon if it's already running" do
    @controller.start
    begin
      socket = @controller.connect do
        TCPSocket.new("localhost", 3230)
      end
      socket.close
    ensure
      @controller.stop
    end
  end
end

describe DaemonController do
  include TestHelper

  after :each do
    @server.close if @server && !@server.closed?
    begin
      File.unlink("spec/foo.sock")
    rescue
      nil
    end
  end

  specify "if the ping command is a block that raises Errno::ECONNREFUSED, then that's " \
    "an indication that the daemon cannot be connected to" do
    new_controller(ping_command: lambda do
      raise Errno::ECONNREFUSED, "dummy"
    end)
    expect(@controller.send(:run_ping_command)).to be false
  end

  specify "if the ping command is a block that returns an object that responds to #close, " \
    "then the close method will be called on that object" do
    @server = TCPServer.new("localhost", 8278)
    socket = nil
    new_controller(ping_command: lambda do
      socket = TCPSocket.new("localhost", 8278)
    end)
    @controller.send(:run_ping_command)
    expect(socket).to be_closed
  end

  specify "if the ping command is a block that returns an object that responds to #close, " \
    "and #close raises an exception, then that exception is ignored" do
    @server = TCPServer.new("localhost", 8278)
    o = Object.new
    expect(o).to receive(:close) { raise StandardError, "foo" }
    new_controller(ping_command: lambda do
      o
    end)
    expect { @controller.send(:run_ping_command) }.not_to raise_error
  end

  specify "the ping command may be [:tcp, hostname, port]" do
    new_controller(ping_command: [:tcp, "127.0.0.1", 8278])
    expect(@controller.send(:run_ping_command)).to be false

    @server = TCPServer.new("127.0.0.1", 8278)
    expect(@controller.send(:run_ping_command)).to be true
  end

  if DaemonController.can_ping_unix_sockets?
    specify "the ping command may be [:unix, filename]" do
      new_controller(ping_command: [:unix, "spec/foo.sock"])
      expect(@controller.send(:run_ping_command)).to be false

      @server = UNIXServer.new("spec/foo.sock")
      expect(@controller.send(:run_ping_command)).to be true
    end
  else
    specify "a ping command of type [:unix, filename] is not supported on this Ruby implementation" do
      new_controller(ping_command: [:unix, "spec/foo.sock"])
      @server = UNIXServer.new("spec/foo.sock")
      expect { @controller.send(:run_ping_command) }.to raise_error(
        "Pinging Unix domain sockets is not supported on this Ruby implementation"
      )
    end
  end
end
