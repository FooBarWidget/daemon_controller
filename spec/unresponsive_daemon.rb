#!/usr/bin/env ruby
# frozen_string_literal: true

dir = File.dirname(__FILE__)
Dir.chdir(File.dirname(dir))

Signal.trap("SIGTERM", "IGNORE") if ARGV.include?("--ignore-sigterm")

File.open("spec/echo_server.pid", "w") do |f|
  f.puts(Process.pid)
end
sleep 60
