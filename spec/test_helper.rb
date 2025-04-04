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
  def new_controller(options = {})
    @start_command = String.new("./spec/run_echo_server -l spec/echo_server.log")
    if options[:log_message1]
      @start_command << " --log-message1 #{Shellwords.escape options[:log_message1]}"
    end
    if options[:log_message2]
      @start_command << " --log-message2 #{Shellwords.escape options[:log_message2]}"
    end
    if options[:wait1]
      @start_command << " --wait1 #{options[:wait1]}"
    end
    if options[:wait2]
      @start_command << " --wait2 #{options[:wait2]}"
    end
    if options[:stop_time]
      @start_command << " --stop-time #{options[:stop_time]}"
    end
    if options[:crash_before_bind]
      @start_command << " --crash-before-bind"
    end
    if options[:crash_signal]
      @start_command << " --crash-signal #{options[:crash_signal]}"
    end
    if options[:no_daemonize]
      @start_command << " --no-daemonize"
    end
    if !options[:no_write_pid_file]
      @start_command << " -P spec/echo_server.pid"
    end
    new_options = {
      identifier: "My Test Daemon",
      start_command: @start_command,
      ping_command: method(:ping_echo_server),
      pid_file: "spec/echo_server.pid",
      log_file: "spec/echo_server.log",
      start_timeout: 30,
      stop_timeout: 30
    }.merge(options)
    @controller = DaemonController.new(new_options)
  end

  def ping_echo_server
    TCPSocket.new("127.0.0.1", 3230)
    true
  rescue SystemCallError
    false
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
    deadline = Time.now + deadline_duration
    while Time.now < deadline
      if yield
        return
      else
        sleep(check_interval)
      end
    end
    raise "Time limit exceeded"
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
