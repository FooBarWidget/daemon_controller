#!/usr/bin/env ruby
# frozen_string_literal: true

# A simple echo server, used by the unit test.
require "socket"
require "optparse"

options = {
  port: 3230,
  chdir: "/",
  log_file: "/dev/null",
  wait1: 0,
  wait2: 0,
  stop_time: 0,
  daemonize: true
}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: echo_server.rb [options]"
  opts.separator ""

  opts.separator "Options:"
  opts.on("-p", "--port PORT", Integer, "Port to use. Default: 3230") do |value|
    options[:port] = value
  end
  opts.on("-C", "--change-dir DIR", String, "Change working directory. Default: /") do |value|
    options[:chdir] = value
  end
  opts.on("-l", "--log-file FILENAME", String, "Log file to use. Default: /dev/null") do |value|
    options[:log_file] = value
  end
  opts.on("-P", "--pid-file FILENAME", String, "Pid file to use.") do |value|
    options[:pid_file] = File.absolute_path(value)
  end
  opts.on("--log-message1 MESSAGE", String, "Log message before opening log file.") do |value|
    options[:log_message1] = value
  end
  opts.on("--log-message2 MESSAGE", String, "Log message after opening log file.") do |value|
    options[:log_message2] = value
  end
  opts.on("--wait1 SECONDS", Float, "Wait a few seconds before writing pid file.") do |value|
    options[:wait1] = value
  end
  opts.on("--wait2 SECONDS", Float, "Wait a few seconds before binding server socket.") do |value|
    options[:wait2] = value
  end
  opts.on("--stop-time SECONDS", Float, "Wait a few seconds before exiting.") do |value|
    options[:stop_time] = value
  end
  opts.on("--crash-before-bind", "Whether the daemon should crash before binding the server socket.") do
    options[:crash_before_bind] = true
  end
  opts.on("--crash-signal SIGNAL", "Signal to send to the daemon when crashing.") do |value|
    options[:crash_signal] = value
  end
  opts.on("--no-daemonize", "Don't daemonize.") do
    options[:daemonize] = false
  end
  opts.on("--ignore-sigterm", "Ignore SIGTERM.") do
    options[:ignore_sigterm] = true
  end
end
begin
  parser.parse!
rescue OptionParser::ParseError => e
  puts e
  puts
  puts "Please see '--help' for valid options."
  exit 1
end

if options[:pid_file]
  if File.exist?(options[:pid_file])
    warn "*** ERROR: pid file #{options[:pid_file]} exists."
    exit 1
  end
end

if options[:log_message1]
  puts options[:log_message1]
  $stdout.flush
end

if options[:ignore_sigterm]
  Signal.trap("SIGTERM", "IGNORE")
end

sleep(options[:wait1])

if ENV["ENV_FILE"]
  options[:env_file] = File.absolute_path(ENV["ENV_FILE"])
end

def main(options)
  $stdin.reopen("/dev/null", "r")
  $stdout.reopen(options[:log_file], "a")
  $stderr.reopen(options[:log_file], "a")
  $stdout.sync = true
  $stderr.sync = true
  Dir.chdir(options[:chdir])
  File.umask(0)

  if options[:log_message2]
    puts options[:log_message2]
  end

  if options[:env_file]
    File.write(options[:env_file], "\0")
    at_exit do
      File.unlink(options[:env_file])
    rescue
      nil
    end
  end

  if options[:pid_file]
    File.open(options[:pid_file], "w") do |f|
      f.puts(Process.pid)
    end
  end

  sleep(options[:wait2])
  if options[:crash_before_bind]
    puts "#{Time.now}: crashing, as instructed."
    if options[:crash_signal]
      Process.kill(options[:crash_signal], Process.pid)
    end
    exit 2
  end

  server = TCPServer.new("127.0.0.1", options[:port])
  begin
    puts "*** #{Time.now}: echo server started"
    while (client = server.accept)
      puts "#{Time.now}: new client"
      begin
        while (line = client.readline)
          puts "#{Time.now}: client sent: #{line.strip}"
          client.puts(line)
        end
      rescue EOFError
      ensure
        puts "#{Time.now}: connection closed"
        begin
          client.close
        rescue
          nil
        end
      end
    end
  rescue SignalException
    exit 2
  rescue => e
    puts e
    puts "    " + e.backtrace.join("\n    ")
    exit 3
  ensure
    puts "*** #{Time.now}: echo server exiting..."
    sleep(options[:stop_time])
    puts "*** #{Time.now}: echo server exited"
  end
end

if options[:daemonize]
  fork do
    Process.setsid
    main(options)
  end
else
  main(options)
end
