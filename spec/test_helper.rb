# frozen_string_literal: true

require "shellwords"

root = File.absolute_path(File.join(File.dirname(__FILE__), ".."))
Dir.chdir(root)

# Ensure subprocesses (with could be a different Ruby) are
# started without Bundler environment variables.
ENV.replace(Bundler.with_unbundled_env { ENV.to_h.dup })

if !ENV["MRI_RUBY"]
  if RUBY_PLATFORM.match?(/java/)
    # We need a Ruby implementation that starts fast and supports forking.
    # JRuby is neither.
    abort "In order to run these tests in JRuby, you must set " \
      "the environment variable $MRI_RUBY to an MRI Ruby interpeter."
  else
    require "rbconfig"
    rb_config = defined?(RbConfig) ? RbConfig::CONFIG : Config::CONFIG
    ENV["MRI_RUBY"] = rb_config["bindir"] + "/" + rb_config["RUBY_INSTALL_NAME"] +
      rb_config["EXEEXT"]
    puts ENV["MRI_RUBY"]
  end
end

trap("SIGQUIT") do
  if Thread.respond_to?(:list)
    output = String.new("----- #{Time.now} -----\n")
    Thread.list.each do |thread|
      output << "##### #{thread}\n"
      output << thread.backtrace.join("\n")
      output << "\n\n"
    end
    output << "--------------------"
    warn(output)
    $stderr.flush
  end
end

module TestHelper
  def new_logger
    @logger ||= begin
      @log_stream = StringIO.new
      logger = Logger.new(@log_stream)
      logger.level = Logger::DEBUG
      logger
    end
  end

  def print_logs(example)
    warn "----- LOGS FOR: #{example.full_description} ----"
    warn @log_stream.string
    warn "----- END LOGS -----"
  end

  def new_controller(options = {})
    @start_command = String.new("./spec/run_in_mri_ruby echo_server.rb -l spec/echo_server.log")
    if (log_message1 = options.delete(:log_message1))
      @start_command << " --log-message1 #{Shellwords.escape log_message1}"
    end
    if (log_message2 = options.delete(:log_message2))
      @start_command << " --log-message2 #{Shellwords.escape log_message2}"
    end
    if (wait1 = options.delete(:wait1))
      @start_command << " --wait1 #{wait1}"
    end
    if (wait2 = options.delete(:wait2))
      @start_command << " --wait2 #{wait2}"
    end
    if (stop_time = options.delete(:stop_time))
      @start_command << " --stop-time #{stop_time}"
    end
    if options.delete(:crash_before_bind)
      @start_command << " --crash-before-bind"
    end
    if (crash_signal = options.delete(:crash_signal))
      @start_command << " --crash-signal #{crash_signal}"
    end
    if options.delete(:no_daemonize)
      @start_command << " --no-daemonize"
    end
    if options.delete(:ignore_sigterm)
      @start_command << " --ignore-sigterm"
    end
    if !options.delete(:no_write_pid_file)
      @start_command << " -P spec/echo_server.pid"
    end
    new_options = {
      identifier: "My Test Daemon",
      start_command: @start_command,
      ping_command: method(:ping_echo_server),
      pid_file: "spec/echo_server.pid",
      log_file: "spec/echo_server.log",
      start_timeout: 30,
      stop_timeout: 30,
      logger: new_logger
    }.merge(options)
    @controller = DaemonController.new(**new_options)
  end

  def ping_echo_server
    TCPSocket.new("127.0.0.1", 3230)
    true
  rescue SystemCallError
    false
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def write_file(filename, contents)
    File.write(filename, contents)
  end

  def exec_is_slow?
    RUBY_PLATFORM == "java"
  end

  def process_is_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue SystemCallError
    true
  end

  def eventually(deadline_duration = 1, check_interval = 0.05)
    deadline = monotonic_time + deadline_duration
    while monotonic_time < deadline
      if yield
        return
      else
        sleep(check_interval)
      end
    end
    raise "Time limit exceeded"
  end

  def wait_until_pid_file_available
    eventually(30) do
      @controller.send(:pid_file_available?)
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
end

# A thread which doesn't execute its block until the
# 'go!' method has been called.
class WaitingThread < Thread
  def initialize
    @mutex = Mutex.new
    @cond = ConditionVariable.new
    @go = false
    super do
      @mutex.synchronize do
        until @go
          @cond.wait(@mutex)
        end
      end
      yield
    end
  end

  def go!
    @mutex.synchronize do
      @go = true
      @cond.broadcast
    end
  end
end
